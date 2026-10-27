import 'gst/gst_diary/services/gst_diary_d1_sync_service.dart';
import "web_live_sync/sub_views/web_accounts/services/web_voucher_d1_sync_service.dart";
import 'logic/app_accounts_calculator.dart';
import 'logic/master_cascade_service.dart';
import 'logic/product_integrity_service.dart';
import 'logic/party_integrity_service.dart';
import 'sync_core/modules/party_sync_module.dart';
import 'sync_core/modules/company_sync_module.dart';
import 'sync_core/modules/salt_sync_module.dart';
import 'sync_core/modules/route_sync_module.dart';
import 'sync_core/modules/medicine_sync_module.dart';
import "sync_core/d1_sales_ledger_service.dart";
import "sync_core/outbox/sync_queue_manager.dart";
import 'sync_core/modules/sales_sync_module.dart';
import 'sync_core/modules/purchase_sync_module.dart';
import 'sync_core/modules/sale_challan_sync_module.dart';
import 'sync_core/modules/purchase_challan_sync_module.dart';
import 'sync_core/modules/challan_sync_module.dart';
import 'sync_core/modules/voucher_sync_module.dart';
import 'sync_core/modules/returns_sync_module.dart';
import 'sync_core/modules/credit_note_sync_module.dart';
import 'sync_core/modules/debit_note_sync_module.dart';
import 'sync_core/modules/batch_sync_module.dart';
import 'sync_core/modules/batch_delta_merge_module.dart';
import 'event_sync_lab/workflow/lab_sync_orchestrator.dart';
// FILE: lib/pharoah_manager.dart (FULLY INTEGRATED, COMPILE-SAFE VERSION)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:local_auth/local_auth.dart'; 
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; // REQUIRED IMPORT

import 'models.dart';
import 'gst/gst_diary/gst_diary_models.dart';
import 'administration/system_user_model.dart';
import 'finance/bank_transaction_model.dart';
import 'demo_data.dart';
import 'inventory_logic_center.dart';
import 'fy_transfer_engine.dart';
import 'sync_core/multi_fy_cloud_vault.dart';
import 'gateway/company_registry_model.dart';
import 'logic/app_settings_model.dart';
import 'logic/pharoah_numbering_engine.dart';
import 'master_data_library.dart';
import 'batch_sync_engine.dart';
import 'web_live_sync/web_sync_engine.dart';
import 'web_live_sync/weblivetoken.dart';
import 'app_date_logic.dart';
import 'sync_bridge/engines/app_auto_sync_daemon.dart';
import 'realtime_signaling/coordinators/app_realtime_coordinator.dart';
import 'web_live_sync/sync_protocol/tombstone_engine.dart';
import 'web_live_sync/sync_protocol/snapshot_watcher.dart';

class PharoahManager with ChangeNotifier {
  // ===========================================================================
  // 1. GLOBAL STATE & SECURITY VARIABLES (CLASS LEVEL)
  // ===========================================================================
  
  String activeModule = "HOME"; 
  // --- CONDITIONAL BATCH FILTER WATCHDOG (NEW) ---
  // Yeh tabhi true dega jab company ke paas 1 se zyada Financial Years honge
  bool get showBatchFilter => activeCompany != null && activeCompany!.fYears.length > 1;
  
  // --- 🛡️ NEW SECURITY & AUTO-LOCK STATE ---
  bool isAppLocked = false;           
  Timer? _inactivityTimer; 
  Timer? _backgroundLockTimer;
  final _auth = LocalAuthentication(); 
  final _secureStorage = const FlutterSecureStorage(); 

  // --- DATA LISTS ---
  List<Medicine> medicines = [];
  List<Salesman> salesmen = []; 
  List<SystemUser> systemUsers = []; 
  SystemUser? loggedInStaff;
  List<Party> parties = []; 
  List<RouteArea> routes = []; 
  List<Company> companies = [];
  List<Salt> salts = []; 
  List<DrugType> drugTypes = []; 
  List<Bank> banks = [];
  List<ChequeEntry> cheques = []; 
  List<ShortageItem> shortages = [];
  List<NumberingSeries> numberingSeries = []; 
  List<Sale> sales = [];
  List<GstDiarySession> gstDiarySessions = []; 
  List<Purchase> purchases = [];
  List<SaleChallan> saleChallans = []; 
  List<PurchaseChallan> purchaseChallans = [];
  List<SaleReturn> saleReturns = []; 
  List<PurchaseReturn> purchaseReturns = [];
  List<Voucher> vouchers = []; 
  List<LogEntry> logs = []; 
  Map<String, List<BatchInfo>> batchHistory = {};
  AppConfig config = AppConfig(); 
  List<CompanyProfile> companiesRegistry = [];
  CompanyProfile? activeCompany; 
  String currentFY = ""; 
  bool isAdminAuthenticated = false;

  PharoahManager() { initRegistry(); }

  // ===========================================================================
  // 2. NAVIGATION & DYNAMIC MENU GETTERS
  // ===========================================================================

  
  void rebuildInventory() {
    InventoryLogicCenter.rebuildAllInventory(
      medicines: medicines,
      batchHistory: batchHistory,
      purchases: purchases,
      sales: sales,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
    );
    notifyListeners();
  }

  void updateModule(String newModule) {
    activeModule = newModule;
    notifyListeners();
  }

  List<ModuleAction> get mainMenuActions => [
    ModuleAction(title: "BILLING", icon: Icons.receipt_long, color: Colors.blue, navModule: "BILLING"),
    ModuleAction(title: "CHALLANS", icon: Icons.local_shipping, color: Colors.teal, navModule: "CHALLANS"),
    ModuleAction(title: "RETURNS", icon: Icons.assignment_return, color: Colors.red, navModule: "RETURNS"),
    ModuleAction(title: "INVENTORY", icon: Icons.inventory, color: Colors.purple, navModule: "INVENTORY"),
    ModuleAction(title: "ACCOUNTS", icon: Icons.account_balance_wallet, color: Colors.indigo, navModule: "ACCOUNTS"),
    ModuleAction(title: "MASTERS", icon: Icons.stars, color: Colors.orange, navModule: "MASTERS"),
    ModuleAction(title: "MODIFICATIONS", icon: Icons.edit_note_rounded, color: Colors.blueGrey, navModule: "GO_MODIFICATION"),
    ModuleAction(title: "GST", icon: Icons.verified, color: Colors.green, navModule: "GST"),
    ModuleAction(title: "DATA HUB", icon: Icons.cloud_sync, color: Colors.teal, navModule: "GO_DATA_HUB"),
  ];

  List<ModuleAction> get billingActions => [
    ModuleAction(title: "New Sale", icon: Icons.add_shopping_cart, color: Colors.blue, navModule: "GO_SALE"),
    ModuleAction(title: "Purchase", icon: Icons.downloading, color: Colors.orange, navModule: "GO_PURCHASE"),
    ModuleAction(title: "STITCHER", icon: Icons.auto_fix_high, color: Colors.teal, navModule: "GO_STITCHER_WIZARD"),
    ModuleAction(title: "Sale Reg", icon: Icons.description, color: Colors.blue, navModule: "GO_SALE_REG"),
    ModuleAction(title: "Pur Reg", icon: Icons.history, color: Colors.brown, navModule: "GO_PUR_REG"),
  ];

  List<ModuleAction> get challanActions => [
    ModuleAction(title: "Sale Challan", icon: Icons.local_shipping, color: Colors.teal, navModule: "GO_CHALLAN_SALE"),
    ModuleAction(title: "Pur Challan", icon: Icons.inventory_2, color: Colors.orange, navModule: "GO_CHALLAN_PUR"),
    ModuleAction(title: "Sale Reg", icon: Icons.list, color: Colors.indigo, navModule: "GO_CHALLAN_SALE_REG"),
    ModuleAction(title: "Pur Reg", icon: Icons.history_edu, color: Colors.amber, navModule: "GO_CHALLAN_PUR_REG"),
  ];

  List<ModuleAction> get returnActions => [
    ModuleAction(title: "Credit Note", icon: Icons.assignment_return, color: Colors.red, navModule: "GO_RETURN_SALE"),
    ModuleAction(title: "Debit Note", icon: Icons.remove_shopping_cart, color: Colors.brown, navModule: "GO_RETURN_PUR"),
    ModuleAction(title: "Return Reg", icon: Icons.format_list_bulleted, color: Colors.red.shade900, navModule: "GO_RETURN_SALE_REG"),
  ];

  List<ModuleAction> get inventoryActions => [
    ModuleAction(title: "Stock", icon: Icons.view_in_ar, color: Colors.purple, navModule: "GO_STOCK"),
    ModuleAction(title: "Shortage", icon: Icons.trending_down, color: Colors.red, navModule: "GO_SHORTAGE"),
    ModuleAction(title: "Ledger", icon: Icons.menu_book, color: Colors.blueGrey, navModule: "GO_ITEM_LEDGER"),
  ];

  List<ModuleAction> get accountsActions => [
    ModuleAction(title: "Daybook", icon: Icons.event_note, color: Colors.blueGrey, navModule: "GO_DAYBOOK"),
    ModuleAction(title: "Ledgers", icon: Icons.people, color: Colors.indigo, navModule: "GO_LEDGERS"),
    ModuleAction(title: "Receipts", icon: Icons.add_chart, color: Colors.green, navModule: "GO_RECEIPT"),
    ModuleAction(title: "Payments", icon: Icons.analytics, color: Colors.red, navModule: "GO_PAYMENT"),
    ModuleAction(title: "Audit History", icon: Icons.history_edu_rounded, color: Colors.orange.shade900, navModule: "GO_HISTORY"),
    ModuleAction(title: "STATEMENTS", icon: Icons.analytics_rounded, color: Colors.indigo.shade900, navModule: "GO_STATEMENT_HUB"),
  ];

  List<ModuleAction> get mastersActions => [
    ModuleAction(title: "Parties", icon: Icons.group_add, color: Colors.indigo, navModule: "GO_M_PARTY"),
    ModuleAction(title: "Items", icon: Icons.medication, color: Colors.purple, navModule: "GO_M_ITEM"),
    ModuleAction(title: "Series", icon: Icons.format_list_numbered, color: Colors.blue, navModule: "GO_M_SERIES"),
    ModuleAction(title: "Staff", icon: Icons.admin_panel_settings, color: Colors.red, navModule: "GO_M_STAFF"),
    ModuleAction(title: "User Control", icon: Icons.security_rounded, color: Colors.red.shade900, navModule: "GO_USER_CONTROL"),
    ModuleAction(title: "Batches", icon: Icons.layers, color: Colors.blueGrey, navModule: "GO_M_BATCH"),
    ModuleAction(title: "CA Profile", icon: Icons.assignment_ind_rounded, color: Colors.orange.shade900, navModule: "GO_CA_PROFILE"),
    ModuleAction(title: "Routes", icon: Icons.map, color: Colors.teal, navModule: "GO_M_ROUTE"),
    ModuleAction(title: "Company", icon: Icons.business, color: Colors.brown, navModule: "GO_M_COMP"),
    ModuleAction(title: "Salt Master", icon: Icons.science, color: Colors.deepOrange, navModule: "GO_M_SALT"),
  ];

  List<ModuleAction> get gstActions => [
    ModuleAction(title: "GSTR-1", icon: Icons.assignment, color: Colors.green, navModule: "GO_GST_1"),
    ModuleAction(title: "GSTR-3B", icon: Icons.summarize, color: Colors.blue, navModule: "GO_GST_3B"),
    ModuleAction(title: "GSTR-2", icon: Icons.shopping_cart_checkout_rounded, color: const Color(0xFFD97706), navModule: "GO_GST_2"),
    ModuleAction(title: "Portal", icon: Icons.fact_check, color: Colors.teal, navModule: "GO_GST_RECON"),
    ModuleAction(title: "E-Way Bill", icon: Icons.local_shipping_outlined, color: const Color(0xFF6366F1), navModule: "GO_EWAY"),
    if (config.developerAllowGstDiaryToUser && config.userEnableGstDiary)
      ModuleAction(title: "GST Diary", icon: Icons.menu_book_rounded, color: const Color(0xFF8B5CF6), navModule: "GO_GST_DIARY"),
  ];

  // ===========================================================================
  // 3. SECURITY & AUTH LOGIC
  // ===========================================================================

  void authenticateAdmin(bool status) { 
    isAdminAuthenticated = status; 
    if (status) {
      isAppLocked = false;
      resetInactivityTimer();
    }
    notifyListeners(); 
  }

  void resetInactivityTimer() {
    if (activeCompany == null || activeCompany!.autoLockMinutes == 0) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(Duration(minutes: activeCompany!.autoLockMinutes), () {
      lockApp(); 
    });
  }

  void lockApp() {
    if (isAppLocked || activeCompany == null) return;
    isAppLocked = true;
    notifyListeners();
  }

  Future<bool> authenticateBiometric() async {
    try {
      bool canCheck = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canCheck) return false;
      bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Scan fingerprint to unlock ERP',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
      if (didAuthenticate) {
        isAppLocked = false;
        resetInactivityTimer();
        notifyListeners();
      }
      return didAuthenticate;
    } catch (e) { return false; }
  }

  Future<void> saveSecureToken(String password) async {
    if (activeCompany == null) return;
    await _secureStorage.write(key: 'auth_${activeCompany!.id}', value: password);
  }

  Future<String?> getSecureToken() async {
    if (activeCompany == null) return null;
    return await _secureStorage.read(key: 'auth_${activeCompany!.id}');
  }

  void handleAppLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (activeCompany != null && activeCompany!.autoLockMinutes > 0) {
        _backgroundLockTimer?.cancel();
        _backgroundLockTimer = Timer(const Duration(seconds: 60), () {
          lockApp(); 
        });
      }
    } 
    else if (state == AppLifecycleState.resumed) {
      _backgroundLockTimer?.cancel(); 
      debugPrint("🛡️ System: Welcome back! Lock cancelled via Grace Period.");
    }
  }

  // ===========================================================================
  // 4. REGISTRY & PERSISTENCE
  // ===========================================================================

  Future<void> initRegistry() async {
    final root = await getApplicationDocumentsDirectory(); 
    final file = File('${root.path}/pharoah_registry.json');
    if (await file.exists()) { 
      try { 
        List l = jsonDecode(await file.readAsString()); 
        companiesRegistry = l.map((e) => CompanyProfile.fromMap(e)).toList(); 
      } catch (e) { debugPrint("Registry error: $e"); } 
    }
    notifyListeners();
  }

  Future<void> saveRegistry() async {
    final root = await getApplicationDocumentsDirectory();
    await File('${root.path}/pharoah_registry.json').writeAsString(jsonEncode(companiesRegistry.map((e) => e.toMap()).toList()));
    notifyListeners();
  }

  
  Future<void> switchYear(String year) async {
    currentFY = year;
    if (activeCompany != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_fy_${activeCompany!.id}', year);
    }
    await loadAllData();
  }

  Future<void> loginToCompany(CompanyProfile c, String fy) async { 
    activeCompany = c; 
    currentFY = fy; 
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_fy_${c.id}', fy); 
    await prefs.setString('last_active_fy_for_${c.id}', fy); 
    
    await loadAllData(); 
  }

  void clearSession() { 
    activeCompany = null; 
    currentFY = ""; 
    isAdminAuthenticated = false; 
    isAppLocked = false;
    _inactivityTimer?.cancel();
    loggedInStaff = null; 
    AppRealtimeCoordinator.instance.stop();
    AppAutoSyncDaemon.instance.stop();
    notifyListeners(); 
  }

  Future<String> getWorkingPath() async {
    if (activeCompany == null || currentFY.isEmpty) return "";
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/Pharoah_Data/${activeCompany!.id}/${activeCompany!.businessType}/$currentFY');
    if (!await dir.exists()) await dir.create(recursive: true); 
    return dir.path;
  }

  Future<void> save() async {
    final dir = await getWorkingPath(); 
    if (dir.isEmpty) return;
    Future _w(String n, List data) async => await File('$dir/$n').writeAsString(jsonEncode(data.map((e) => e.toMap()).toList()));
    
    await _w('meds.json', medicines); 
    await _w('parts.json', parties); 
    await _w('sales.json', sales);
    await _w('purc.json', purchases); 
    await _w('vouc.json', vouchers); 
    await _w('sys_users.json', systemUsers);
    await _w('series.json', numberingSeries); 
    await _w('s_challan.json', saleChallans); 
    await _w('p_challan.json', purchaseChallans);
    await _w('s_return.json', saleReturns); 
    await _w('p_return.json', purchaseReturns); 
    await _w('cheques.json', cheques);
    await _w('shortage.json', shortages); 
    await _w('logs.json', logs); 
    await _w('routs.json', routes);
    await _w('comps.json', companies); 
    await _w('salts.json', salts); 
    await _w('dtypes.json', drugTypes); 
    await _w('banks.json', banks);
    await _w('gst_sessions.json', gstDiarySessions);
    
    await File('$dir/bats.json').writeAsString(jsonEncode(batchHistory.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))));
    await File('$dir/config.json').writeAsString(jsonEncode(config.toMap()));
    D1SalesLedgerService.activeFinancialYear = currentFY;

    // 🏛️ MARG-STYLE AUTO-CASCADE ON BACK-YEAR EDIT:
    // If user is editing a historical/back Financial Year (e.g. 2025-26), automatically cascade
    // the updated closing balances & batch stocks forward to 2026-27 (and any newer years)!
    if (activeCompany != null &&
        activeCompany!.fYears.length > 1 &&
        currentFY.isNotEmpty &&
        currentFY != activeCompany!.fYears.last) {
      await syncOpeningBalancesFromPreviousYear(
        startYear: currentFY,
        onStepProgress: (_, __) {},
        reloadActiveYearAtEnd: false,
      );
    }

    notifyListeners();
    // ⚡ 1000-IQ ZERO-LAG SILENT AUTO-SYNC (Single Unified Debounced Push via AppRealtimeCoordinator)
    AppRealtimeCoordinator.instance.notifyAppMutation(this);
    LabSyncOrchestrator.instance.addLog("📤 [APP] Queued unified cloud sync push (#PH-REV-787)");
  }

  Future<void> loadAllData() async {
    final dir = await getWorkingPath(); 
    if (dir.isEmpty) return;
    D1SalesLedgerService.activeFinancialYear = currentFY;
    SharedPreferences.getInstance().then((prefs) {
      final bool pausedByUser = prefs.getBool('is_cloud_sync_paused_by_user') ?? false;
      if (!pausedByUser) {
        prefs.setBool('is_live_web_active', true);
      }
    });
    dynamic load(String n) { final f = File('$dir/$n'); return f.existsSync() ? jsonDecode(f.readAsStringSync()) : null; }
    
    var cData = load('config.json');
    if (cData != null) config = AppConfig.fromMap(cData);
    else config = AppConfig();
    
    medicines = (load('meds.json') as List?)?.map((e) => Medicine.fromMap(e)).toList() ?? DemoData.getMedicines();
    parties = (load('parts.json') as List?)?.map((e) => Party.fromMap(e)).toList() ?? [DemoData.getDemoParty(), Party(id:'cash',name:"CASH",group:"Cash in Hand")];
    companies = (load('comps.json') as List?)?.map((e) => Company.fromMap(e)).toList() ?? MasterDataLibrary.getTopCompanies();
    salts = (load('salts.json') as List?)?.map((e) => Salt.fromMap(e)).toList() ?? MasterDataLibrary.getTopSalts();
    drugTypes = (load('dtypes.json') as List?)?.map((e) => DrugType.fromMap(e)).toList() ?? MasterDataLibrary.getDrugTypes();
    sales = (load('sales.json') as List?)
        ?.map((e) => Sale.fromMap(e))
        .where((s) =>
            !s.id.startsWith('SESS_') &&
            s.id != 'APP_CONFIG_MASTER' &&
            s.billNo.trim().isNotEmpty &&
            !(s.items.isEmpty && s.totalAmount <= 0) &&
            !D1SalesLedgerService.isBillDeleted(s.id, s.billNo))
        .toList() ?? [];
    purchases = (load('purc.json') as List?)
        ?.map((e) => Purchase.fromMap(e))
        .where((p) => !D1SalesLedgerService.isPurchaseDeleted(p.id, p.partyId, p.billNo, p.internalNo))
        .toList() ?? [];
    vouchers = (load('vouc.json') as List?)?.map((e) => Voucher.fromMap(e)).where((v) => v.isDeleted != 1 && !D1SalesLedgerService.isBillDeleted(v.id, v.voucherNo)).toList() ?? [];
    saleChallans = (load('s_challan.json') as List?)
        ?.map((e) => SaleChallan.fromMap(e))
        .where((c) => !D1SalesLedgerService.isBillDeleted(c.id, c.billNo))
        .toList() ?? [];
    purchaseChallans = (load('p_challan.json') as List?)
        ?.map((e) => PurchaseChallan.fromMap(e))
        .where((c) => !D1SalesLedgerService.isPurchaseDeleted(c.id, c.partyId, c.billNo, c.internalNo))
        .toList() ?? [];
    saleReturns = (load('s_return.json') as List?)
        ?.map((e) => SaleReturn.fromMap(e))
        .where((r) => !D1SalesLedgerService.isBillDeleted(r.id, r.billNo))
        .toList() ?? [];
    purchaseReturns = (load('p_return.json') as List?)
        ?.map((e) => PurchaseReturn.fromMap(e))
        .where((r) => !D1SalesLedgerService.isBillDeleted(r.id, r.billNo))
        .toList() ?? [];
    cheques = (load('cheques.json') as List?)?.map((e) => ChequeEntry.fromMap(e)).toList() ?? [];
    shortages = (load('shortage.json') as List?)?.map((e) => ShortageItem.fromMap(e)).toList() ?? [];
    logs = (load('logs.json') as List?)?.map((e) => LogEntry.fromMap(e)).toList() ?? [];
    routes = (load('routs.json') as List?)?.map((e) => RouteArea.fromMap(e)).toList() ?? [];
    banks = (load('banks.json') as List?)?.map((e) => Bank.fromMap(e)).toList() ?? [];
    gstDiarySessions = (load('gst_sessions.json') as List?)?.map((e) => GstDiarySession.fromMap(e)).toList() ?? [];
    
    var sD = load('series.json'); if (sD!=null) numberingSeries = (sD as List).map((e)=>NumberingSeries.fromMap(e)).toList();
    var uD = load('sys_users.json'); if (uD!=null) systemUsers = (uD as List).map((e)=>SystemUser.fromMap(e)).toList();
    var bD = load('bats.json'); if (bD!=null) { batchHistory.clear(); (bD as Map).forEach((k,v)=>batchHistory[k]=(v as List).map((b)=>BatchInfo.fromMap(b)).toList()); }
    
    InventoryLogicCenter.rebuildAllInventory(
      medicines: medicines, 
      batchHistory: batchHistory, 
      purchases: purchases, 
      sales: sales,
      saleReturns: saleReturns,      
      purchaseReturns: purchaseReturns 
    );
    notifyListeners();
    // ⚡ Live Event Bus Listener Active for App (Single Unified Listener)
    AppRealtimeCoordinator.instance.start(this);
  }

  // ===========================================================================
  // 6. BUSINESS LOGIC (SALES, PURCHASES, STITCHER)
  // ===========================================================================

Future<void> finalizeSale({
    required String billNo, 
    required DateTime date, 
    required Party party, 
    required List<BillItem> items, 
    required double total, 
    required String mode, 
    List<String>? linkedIds, 
    double extraDiscount = 0.0, 
    double roundOff = 0.0, 
    String sourceTag = "",
    String? existingId
  }) async { 
    final p = parties.firstWhere((pt) => pt.id == party.id, orElse: () => party);
    if (!parties.any((pt) => pt.id == p.id)) {
      saveOrUpdateParty(p);
    }
    final String sId = (existingId != null && existingId.isNotEmpty) ? existingId : DateTime.now().toString();
    int currentVer = 1;
    final int existingIdx = sales.indexWhere((s) => s.id == sId || s.billNo == billNo);
    if (existingIdx != -1) {
      currentVer = sales[existingIdx].version + 1;
    }
    if (activeCompany != null) {
      await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: sId, secondaryKey: billNo);
    }
    D1SalesLedgerService.unmarkPermanentlyDeleted(sId, billNo);
    sales.removeWhere((s) => s.id == sId || s.billNo == billNo);
    ProductIntegrityService.ensureLineItemsInProductMaster(
      items: items,
      medicines: medicines,
      storeToken: activeCompany != null ? activeCompany!.id : "",
      onMedicineSaved: (m) => saveOrUpdateMedicine(m),
      sourceTag: "SALE",
    );
    final newFinalSale = Sale(
      id: sId, 
      billNo: billNo, 
      partyId: p.id, 
      date: date, 
      partyName: p.name, 
      partyGstin: p.gst, 
      partyState: p.state, 
      items: items, 
      totalAmount: total, 
      paymentMode: mode, 
      linkedChallanIds: linkedIds ?? [], 
      extraDiscount: extraDiscount, 
      roundOff: roundOff, 
      partyAddress: p.address, 
      partyPhone: p.phone, 
      partyEmail: p.email, 
      partyDl: p.dl, 
      partyPan: p.pan, 
      partyCity: p.city, 
      sourceTag: sourceTag,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: currentVer,
    );
    sales.add(newFinalSale);
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          SalesSyncModule.onSaleSaved(newFinalSale, t);
          D1SalesLedgerService.onSaleSaved(newFinalSale, t, isUpdate: existingIdx != -1, clientSource: "APP_MOBILE");
        }
      });
    } 
    
    if (linkedIds != null) { 
      for (var id in linkedIds) { 
        int i = saleChallans.indexWhere((c) => c.id == id || c.billNo == id); 
        if (i != -1) {
          saleChallans[i].status = "Billed";
          saleChallans[i].version += 1;
          saleChallans[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
          if (activeCompany != null) {
            WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
              if (t.isNotEmpty) SaleChallanSyncModule.onSaleChallanSaved(saleChallans[i], t);
            });
          }
        }
      } 
    }
    
    if (sourceTag.isEmpty && activeCompany != null) { 
      String pfx = billNo.split(RegExp(r'\d')).first; 
      await PharoahNumberingEngine.updateSeriesCounter(type: "SALE", companyID: activeCompany!.id, usedNumber: billNo, prefix: pfx); 
    }

    // 🆕 STRICT TWO-WAY SYNC: Billing items ko business key (systemId) ke sath Master me register karein
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey; // "PH-10001" resolved!
      } catch (_) {}

      registerBatchActivity(
        productKey: resolvedKey, 
        batchNo: item.batch, 
        exp: item.exp, 
        packing: item.packing, 
        mrp: item.mrp, 
        rate: item.rate,
        rateA: item.appliedRateType == "A" ? item.rate : 0.0,
        rateB: item.appliedRateType == "B" ? item.rate : 0.0,
        rateC: item.appliedRateType == "C" ? item.rate : 0.0,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }
    
    // Rebuild first, then Save
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    await save(); 
    AppRealtimeCoordinator.instance.notifyAppMutation(
      this,
      action: existingIdx != -1 ? 'SALE_UPDATED' : 'SALE_ADDED',
      entityId: sId,
      unmarkedIds: [sId, if (billNo.trim().isNotEmpty) billNo.trim().toUpperCase()],
    );
    notifyListeners();
  }

Future<void> finalizePurchase({
    required String internalNo, 
    required String billNo, 
    required DateTime date, 
    DateTime? entryDate, 
    required Party party, 
    required List<PurchaseItem> items, 
    required double total, 
    required String mode, 
    List<String>? linkedChallanIds, 
    String sourceTag = "",
    double extraDiscount = 0.0, // 🆕 Mapped
    double roundOff = 0.0,      // 🆕 Mapped
    String? existingId
  }) async { 
    final String pId = (existingId != null && existingId.isNotEmpty) ? existingId : DateTime.now().toString();
    int currentVer = 1;
    final cleanIntNo = internalNo.trim().toUpperCase();
    final cleanBillNo = billNo.trim().toUpperCase();
    if (!parties.any((pt) => pt.id == party.id)) {
      saveOrUpdateParty(party);
    }
    final cleanPartyId = party.id.trim().toUpperCase();
    final compKey2 = (cleanPartyId.isNotEmpty && cleanBillNo.isNotEmpty) ? "${cleanPartyId}_$cleanBillNo" : "";
    final compKey = PurchaseSyncModule.makeCompositeKey(party.id, billNo, internalNo);
    if (activeCompany != null) {
      await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: pId, secondaryKey: compKey);
      if (compKey2.isNotEmpty) await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: compKey2);
      if (cleanBillNo.isNotEmpty) await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: cleanBillNo);
      if (cleanIntNo.isNotEmpty) await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: cleanIntNo);
    }
    D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(pId, party.id, billNo, internalNo);
    if (cleanBillNo.isNotEmpty) D1SalesLedgerService.unmarkPermanentlyDeleted(cleanBillNo);
    final int existingIdx = purchases.indexWhere((p) => 
      p.id == pId || 
      (cleanIntNo.isNotEmpty && p.internalNo.trim().toUpperCase() == cleanIntNo)
    );
    if (existingIdx != -1) {
      currentVer = purchases[existingIdx].version + 1;
    }
    final int d1Known = D1SalesLedgerService.getPurchaseKnownVersion(pId, party.id, billNo, internalNo);
    if (d1Known >= currentVer) currentVer = d1Known + 1;
    D1SalesLedgerService.recordPurchaseKnownVersion(pId, party.id, billNo, currentVer, internalNo);

    purchases.removeWhere((p) => 
      p.id == pId || 
      (cleanIntNo.isNotEmpty && p.internalNo.trim().toUpperCase() == cleanIntNo)
    );
    ProductIntegrityService.ensurePurchaseItemsInProductMaster(
      items: items,
      medicines: medicines,
      storeToken: activeCompany != null ? activeCompany!.id : "",
      onMedicineSaved: (m) => saveOrUpdateMedicine(m),
      sourceTag: "PURCHASE",
    );
    final newFinalPurchase = Purchase(
      id: pId, 
      internalNo: internalNo, 
      billNo: billNo, 
      partyId: party.id, 
      date: date, 
      entryDate: entryDate ?? DateTime.now(), 
      distributorName: party.name, 
      items: items, 
      totalAmount: total, 
      paymentMode: mode, 
      linkedChallanIds: linkedChallanIds ?? [], 
      sourceTag: sourceTag, 
      extraDiscount: extraDiscount, 
      roundOff: roundOff,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: currentVer,
    );
    purchases.add(newFinalPurchase);
    final bool isModify = existingIdx != -1;
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          PurchaseSyncModule.onPurchaseSaved(newFinalPurchase, t);
          D1SalesLedgerService.onPurchaseSaved(newFinalPurchase, t, isUpdate: isModify, clientSource: "APP_MOBILE");
        }
      });
    } 
    
    if (linkedChallanIds != null) { 
       for (var id in linkedChallanIds) { 
         int i = purchaseChallans.indexWhere((c) => c.id == id || c.internalNo == id || c.billNo == id); 
         if (i != -1) {
           purchaseChallans[i].status = "Billed";
           purchaseChallans[i].version += 1;
           purchaseChallans[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
           if (activeCompany != null) {
             WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
               if (t.isNotEmpty) PurchaseChallanSyncModule.onPurchaseChallanSaved(purchaseChallans[i], t);
             });
           }
         }
       } 
     }
    
    if (sourceTag.isEmpty && activeCompany != null) { 
      await PharoahNumberingEngine.updateSeriesCounter(type: "PURCHASE", companyID: activeCompany!.id, usedNumber: internalNo, prefix: "PUR-"); 
    }

    // 🆕 STRICT TWO-WAY SYNC: Purchase items ko business key (systemId) ke sath Master me register karein
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey; // "PH-10001" resolved!
      } catch (_) {}

      registerBatchActivity(
        productKey: resolvedKey, 
        batchNo: item.batch, 
        exp: item.exp, 
        packing: item.packing, 
        mrp: item.mrp, 
        rate: item.purchaseRate,
        rateA: item.rateA,
        rateB: item.rateB,
        rateC: item.rateC,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }
    
    // Rebuild first, then Save
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    await save();
    AppRealtimeCoordinator.instance.notifyAppMutation(
      this,
      action: isModify ? 'PURCHASE_UPDATED' : 'PURCHASE_ADDED',
      entityId: pId,
      unmarkedIds: [
        pId,
        if (cleanIntNo.isNotEmpty) cleanIntNo,
        if (cleanBillNo.isNotEmpty) cleanBillNo,
        if (compKey2.isNotEmpty) compKey2,
        if (compKey.isNotEmpty) compKey,
      ],
    );
    notifyListeners();
  }

  Future<void> updatePurchase({
    required String id, 
    required String internalNo, 
    required String billNo, 
    required DateTime date, 
    DateTime? entryDate, 
    required Party party, 
    required List<PurchaseItem> items, 
    required double total, 
    required String mode, 
    required List<String> linkedChallanIds,
    double extraDiscount = 0.0, // 🆕 Mapped
    double roundOff = 0.0,      // 🆕 Mapped
  }) async { 
    int idx = purchases.indexWhere((p) => p.id == id || (internalNo.isNotEmpty && p.internalNo.trim().toUpperCase() == internalNo.trim().toUpperCase())); 
    if (idx == -1) return; 
    String t = purchases[idx].sourceTag; 
    final cleanIntNo = internalNo.trim().toUpperCase();
    final cleanBillNo = billNo.trim().toUpperCase();
    final cleanPartyId = party.id.trim().toUpperCase();
    final compKey2 = (cleanPartyId.isNotEmpty && cleanBillNo.isNotEmpty) ? "${cleanPartyId}_$cleanBillNo" : "";
    final compKey = PurchaseSyncModule.makeCompositeKey(party.id, billNo, internalNo);
    if (activeCompany != null) {
      await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: id, secondaryKey: compKey);
      if (compKey2.isNotEmpty) await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: compKey2);
      if (cleanBillNo.isNotEmpty) await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: cleanBillNo);
      if (cleanIntNo.isNotEmpty) await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: cleanIntNo);
    }
    D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(id, party.id, billNo, internalNo);
    int maxKnown = D1SalesLedgerService.getPurchaseKnownVersion(id, party.id, billNo, internalNo);
    int nextVer = (purchases[idx].version >= maxKnown ? purchases[idx].version : maxKnown) + 1;
    D1SalesLedgerService.recordPurchaseKnownVersion(id, party.id, billNo, nextVer, internalNo);
    int nowTs = DateTime.now().millisecondsSinceEpoch;

    final updatedPurchase = Purchase(
      id: id, 
      internalNo: internalNo, 
      billNo: billNo, 
      partyId: party.id, 
      date: date, 
      entryDate: entryDate ?? DateTime.now(), 
      distributorName: party.name, 
      items: items, 
      totalAmount: total, 
      paymentMode: mode, 
      linkedChallanIds: linkedChallanIds, 
      sourceTag: t, 
      extraDiscount: extraDiscount, 
      roundOff: roundOff,
      version: nextVer,
      updatedAt: nowTs,
    );
    purchases[idx] = updatedPurchase; 

    // ⚡ Outbox Queue & D1 Edge Dispatch
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((token) {
        if (token.isNotEmpty) {
          PurchaseSyncModule.onPurchaseSaved(updatedPurchase, token);
          D1SalesLedgerService.onPurchaseSaved(updatedPurchase, token, isUpdate: true, clientSource: "APP_MOBILE");
        }
      });
    }

    // Register batch activity for all updated items
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey;
      } catch (_) {}
      registerBatchActivity(
        productKey: resolvedKey, 
        batchNo: item.batch, 
        exp: item.exp, 
        packing: item.packing, 
        mrp: item.mrp, 
        rate: item.purchaseRate,
        rateA: item.rateA,
        rateB: item.rateB,
        rateC: item.rateC,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }
    
    // Rebuild first, then Save & Silent Push
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    await save();
    AppRealtimeCoordinator.instance.notifyAppMutation(
      this,
      action: 'PURCHASE_UPDATED',
      entityId: id,
      unmarkedIds: [
        id,
        if (cleanIntNo.isNotEmpty) cleanIntNo,
        if (cleanBillNo.isNotEmpty) cleanBillNo,
        if (compKey2.isNotEmpty) compKey2,
        if (compKey.isNotEmpty) compKey,
      ],
    );
    notifyListeners();
  }

  Future<void> finalizeBatchSales(List<Sale> batch) async { 
    sales.addAll(batch); 
    for (var s in batch) { 
      if (s.linkedChallanIds.isNotEmpty) { 
        for (var id in s.linkedChallanIds) { 
          int i = saleChallans.indexWhere((c) => c.id == id || c.billNo == id); 
          if (i != -1) {
            saleChallans[i].status = "Billed";
            saleChallans[i].version += 1;
            saleChallans[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
            if (activeCompany != null) {
              WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
                if (t.isNotEmpty) SaleChallanSyncModule.onSaleChallanSaved(saleChallans[i], t);
              });
            }
          }
        } 
      }
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) {
            SalesSyncModule.onSaleSaved(s, t);
            D1SalesLedgerService.onSaleSaved(s, t, clientSource: "APP_MOBILE");
          }
        });
      }
    } 
    if (batch.isNotEmpty && activeCompany != null) { 
      String l = batch.last.billNo; 
      String p = l.split(RegExp(r'\d')).first; 
      await PharoahNumberingEngine.updateSeriesCounter(type: "SALE", companyID: activeCompany!.id, usedNumber: l, prefix: p); 
    } 
    await save(); 
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    notifyListeners(); 
  }

  Future<void> finalizeBatchPurchases(List<Purchase> batch) async { 
    purchases.addAll(batch); 
    for (var p in batch) { 
      if (p.linkedChallanIds.isNotEmpty) { 
        for (var id in p.linkedChallanIds) { 
          int i = purchaseChallans.indexWhere((c) => c.id == id || c.internalNo == id || c.billNo == id); 
          if (i != -1) {
            purchaseChallans[i].status = "Billed";
            purchaseChallans[i].version += 1;
            purchaseChallans[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
            if (activeCompany != null) {
              WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
                if (t.isNotEmpty) PurchaseChallanSyncModule.onPurchaseChallanSaved(purchaseChallans[i], t);
              });
            }
          }
        } 
      }
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) {
            PurchaseSyncModule.onPurchaseSaved(p, t);
            D1SalesLedgerService.onPurchaseSaved(p, t, clientSource: "APP_MOBILE");
          }
        });
      }
    } 
    await save(); 
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    notifyListeners(); 
  }

// --- CHALLANS & RETURNS ---
  Future<void> finalizeSaleChallan({
    required String billNo, 
    required DateTime date, 
    required Party party, 
    required List<BillItem> items, 
    required double total, 
    String remarks = "", 
    required String partyId,
    String? existingId,
  }) async { 
    final String cId = (existingId != null && existingId.isNotEmpty) ? existingId : DateTime.now().toString();
    int currentVer = 1;
    final cleanBNo = billNo.trim().toUpperCase();
    final int existingIdx = saleChallans.indexWhere((c) => c.id == cId || (cleanBNo.isNotEmpty && c.billNo.trim().toUpperCase() == cleanBNo));
    if (existingIdx != -1) {
      currentVer = saleChallans[existingIdx].version + 1;
    }
    if (activeCompany != null) {
      await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: cId, secondaryKey: billNo);
      D1SalesLedgerService.unmarkPermanentlyDeleted(cId, billNo);
    }
    saleChallans.removeWhere((c) => c.id == cId || (cleanBNo.isNotEmpty && c.billNo.trim().toUpperCase() == cleanBNo));
    final newChallan = SaleChallan(
      id: cId, 
      billNo: billNo, 
      partyId: partyId, 
      date: date, 
      partyName: party.name, 
      partyGstin: party.gst, 
      partyState: party.state, 
      items: items, 
      totalAmount: total, 
      remarks: remarks,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: currentVer,
    );
    saleChallans.add(newChallan);
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) SaleChallanSyncModule.onSaleChallanSaved(newChallan, t);
      });
    } 
    
    // 🆕 STRICT TWO-WAY SYNC: Sale Challan items ko correct systemId ke sath Batch Master me register karein
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey; // Mapped to e.g. "PH-10001"
      } catch (_) {}

      registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.rate,
        rateA: item.appliedRateType == "A" ? item.rate : 0.0,
        rateB: item.appliedRateType == "B" ? item.rate : 0.0,
        rateC: item.appliedRateType == "C" ? item.rate : 0.0,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }
    await save();
    AppRealtimeCoordinator.instance.notifyAppMutation(
      this,
      action: 'SALE_CHALLAN_SAVED',
      entityId: cId,
      unmarkedIds: [cId, if (billNo.isNotEmpty) billNo],
    );
  }

  Future<void> finalizePurchaseChallan({
    required String billNo, 
    required String internalNo, 
    required DateTime date, 
    required Party party, 
    required List<PurchaseItem> items, 
    required double total, 
    String remarks = "", 
    required String partyId,
    String? existingId,
  }) async { 
    final String cId = (existingId != null && existingId.isNotEmpty) ? existingId : DateTime.now().toString();
    int currentVer = 1;
    final cleanINo = internalNo.trim().toUpperCase();
    final int existingIdx = purchaseChallans.indexWhere((c) => c.id == cId || (cleanINo.isNotEmpty && c.internalNo.trim().toUpperCase() == cleanINo));
    if (existingIdx != -1) {
      currentVer = purchaseChallans[existingIdx].version + 1;
    }
    final cleanBNo = billNo.trim().toUpperCase();
    final cleanPId = partyId.trim().toUpperCase();
    final compKey2 = (cleanPId.isNotEmpty && cleanBNo.isNotEmpty) ? "${cleanPId}_$cleanBNo" : "";
    final compKey3 = PurchaseChallanSyncModule.makeCompositeKey(cleanPId, cleanBNo, cleanINo);
    if (activeCompany != null) {
      await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: cId, secondaryKey: internalNo);
      if (compKey2.isNotEmpty) await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: compKey2);
      if (compKey3.isNotEmpty) await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: compKey3);
      if (cleanBNo.isNotEmpty) await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: cleanBNo);
      D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(cId, partyId, billNo, internalNo);
      D1SalesLedgerService.unmarkPermanentlyDeleted(cId, billNo, internalNo);
    }
    purchaseChallans.removeWhere((c) => c.id == cId || (cleanINo.isNotEmpty && c.internalNo.trim().toUpperCase() == cleanINo));
    final newPChallan = PurchaseChallan(
      id: cId, 
      internalNo: internalNo, 
      billNo: billNo, 
      partyId: partyId, 
      date: date, 
      distributorName: party.name, 
      items: items, 
      totalAmount: total, 
      remarks: remarks,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: currentVer,
    );
    purchaseChallans.add(newPChallan);
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) PurchaseChallanSyncModule.onPurchaseChallanSaved(newPChallan, t);
      });
    } 
    
    // 🆕 STRICT TWO-WAY SYNC: Purchase Challan items ko correct systemId ke sath Batch Master me register karein
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey; // Mapped to e.g. "PH-10001"
      } catch (_) {}

      registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.purchaseRate,
        rateA: item.rateA,
        rateB: item.rateB,
        rateC: item.rateC,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }
    await save();
    AppRealtimeCoordinator.instance.notifyAppMutation(
      this,
      action: 'PURCHASE_CHALLAN_SAVED',
      entityId: cId,
      unmarkedIds: [cId, if (internalNo.isNotEmpty) internalNo, if (billNo.isNotEmpty) billNo],
    );
  }
  
  // --- NEW CODE ---
// --- NEW CODE ---
  Future<void> finalizeSaleReturn({
    required String billNo, 
    required DateTime date, 
    required Party party, 
    required List<BillItem> items, 
    required double total, 
    double extraDiscount = 0.0, 
    double roundOff = 0.0, 
    String type = "Mixed",
    String? existingId,
  }) async { 
    final String rId = (existingId != null && existingId.isNotEmpty) ? existingId : DateTime.now().toString();
    int currentVer = 1;
    final cleanBNo = billNo.trim().toUpperCase();
    final int existingIdx = saleReturns.indexWhere((r) => r.id == rId || (cleanBNo.isNotEmpty && r.billNo.trim().toUpperCase() == cleanBNo));
    if (existingIdx != -1) {
      currentVer = saleReturns[existingIdx].version + 1;
    }
    if (activeCompany != null) {
      await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: rId, secondaryKey: billNo);
      D1SalesLedgerService.unmarkPermanentlyDeleted(rId, billNo);
    }
    saleReturns.removeWhere((r) => r.id == rId || (cleanBNo.isNotEmpty && r.billNo.trim().toUpperCase() == cleanBNo));
    final newSReturn = SaleReturn(
      id: rId, 
      billNo: billNo, 
      date: date, 
      partyName: party.name, 
      items: items, 
      totalAmount: total, 
      returnType: type, 
      extraDiscount: extraDiscount, 
      roundOff: roundOff, 
      status: "Active",
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: currentVer,
    );
    saleReturns.add(newSReturn);
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) CreditNoteSyncModule.onCreditNoteSaved(newSReturn, t);
      });
    } 
    
    // 🆕 STRICT TWO-WAY SYNC: Sale Return (Credit Note) items ko correct systemId ke sath Batch Master me register karein
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey; // Resolved to "PH-10001"
      } catch (_) {}

      registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.rate,
        rateA: item.appliedRateType == "A" ? item.rate : 0.0,
        rateB: item.appliedRateType == "B" ? item.rate : 0.0,
        rateC: item.appliedRateType == "C" ? item.rate : 0.0,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }

    // Rebuild first, then Save
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    await save();
    AppRealtimeCoordinator.instance.notifyAppMutation(
      this,
      action: 'SALE_RETURN_SAVED',
      entityId: rId,
      unmarkedIds: [rId, if (billNo.isNotEmpty) billNo],
    );
    notifyListeners();
  }

  Future<void> finalizePurchaseReturn({
    required String billNo, 
    required DateTime date, 
    required Party party, 
    required List<PurchaseItem> items, 
    required double total, 
    double extraDiscount = 0.0, 
    double roundOff = 0.0, 
    String type = "Mixed",
    String? existingId,
  }) async { 
    final String rId = (existingId != null && existingId.isNotEmpty) ? existingId : DateTime.now().toString();
    int currentVer = 1;
    final cleanBNo = billNo.trim().toUpperCase();
    final int existingIdx = purchaseReturns.indexWhere((r) => r.id == rId || (cleanBNo.isNotEmpty && r.billNo.trim().toUpperCase() == cleanBNo));
    if (existingIdx != -1) {
      currentVer = purchaseReturns[existingIdx].version + 1;
    }
    if (activeCompany != null) {
      await TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: rId, secondaryKey: billNo);
      D1SalesLedgerService.unmarkPermanentlyDeleted(rId, billNo);
    }
    purchaseReturns.removeWhere((r) => r.id == rId || (cleanBNo.isNotEmpty && r.billNo.trim().toUpperCase() == cleanBNo));
    final newPReturn = PurchaseReturn(
      id: rId, 
      billNo: billNo, 
      distributorName: party.name, 
      date: date, 
      items: items, 
      totalAmount: total, 
      status: "Active", 
      returnType: type, 
      extraDiscount: extraDiscount, 
      roundOff: roundOff, 
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: currentVer,
    );
    purchaseReturns.add(newPReturn);
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) DebitNoteSyncModule.onDebitNoteSaved(newPReturn, t);
      });
    } 
    
    // 🆕 STRICT TWO-WAY SYNC: Purchase Return (Debit Note) items ko correct systemId ke sath Batch Master me register karein
    for (var item in items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey; // Resolved to "PH-10001"
      } catch (_) {}

      registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.purchaseRate,
        rateA: item.rateA,
        rateB: item.rateB,
        rateC: item.rateC,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }

    // Rebuild first, then Save
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    await save();
    AppRealtimeCoordinator.instance.notifyAppMutation(
      this,
      action: 'PURCHASE_RETURN_SAVED',
      entityId: rId,
      unmarkedIds: [rId, if (billNo.isNotEmpty) billNo],
    );
    notifyListeners();
  }
  // ===========================================================================
  // 7. BATCH TOOLS & INVENTORY INTEL
  // ===========================================================================

void registerBatchActivity({
    required String productKey, 
    required String batchNo, 
    required String exp, 
    required String packing, 
    required double mrp, 
    required double rate,
    double rateA = 0.0,
    double rateB = 0.0,
    double rateC = 0.0,
    double rateCFormula = 0.0,
    String appliedRateType = "A",
    double qtyChange = 0.0,
    String status = "Active",
  }) {
    // Direct delegation to BatchSyncEngine (Centralized safe sync)
    BatchSyncEngine.registerBatchActivity(
      ph: this,
      productKey: productKey,
      batchNo: batchNo,
      exp: exp,
      packing: packing,
      mrp: mrp,
      rate: rate,
      rateA: rateA,
      rateB: rateB,
      rateC: rateC,
      rateCFormula: rateCFormula,
      appliedRateType: appliedRateType,
      qtyChange: qtyChange,
      status: status,
    );
  }

  void autoHydrateBatchHistoryFromTransactions() {
    bool hasUpdates = false;

    void processBillItems(List<BillItem> items) {
      for (var item in items) {
        if (item.batch.trim().isEmpty) continue;
        String resolvedKey = item.medicineID;
        try {
          final med = medicines.firstWhere((m) => m.id == item.medicineID || m.name.trim().toUpperCase() == item.name.trim().toUpperCase());
          resolvedKey = med.identityKey;
        } catch (_) {}
        if (resolvedKey.isEmpty) resolvedKey = item.name.trim().toUpperCase();

        registerBatchActivity(
          productKey: resolvedKey,
          batchNo: item.batch,
          exp: item.exp,
          packing: item.packing,
          mrp: item.mrp,
          rate: item.rate,
          appliedRateType: item.appliedRateType,
          rateCFormula: item.rateCFormula,
        );
        hasUpdates = true;
      }
    }

    void processPurchaseItems(List<PurchaseItem> items) {
      for (var item in items) {
        if (item.batch.trim().isEmpty) continue;
        String resolvedKey = item.medicineID;
        try {
          final med = medicines.firstWhere((m) => m.id == item.medicineID || m.name.trim().toUpperCase() == item.name.trim().toUpperCase());
          resolvedKey = med.identityKey;
        } catch (_) {}
        if (resolvedKey.isEmpty) resolvedKey = item.name.trim().toUpperCase();

        registerBatchActivity(
          productKey: resolvedKey,
          batchNo: item.batch,
          exp: item.exp,
          packing: item.packing,
          mrp: item.mrp,
          rate: item.purchaseRate,
          rateA: item.rateA,
          rateB: item.rateB,
          rateC: item.rateC,
          appliedRateType: item.appliedRateType,
          rateCFormula: item.rateCFormula,
        );
        hasUpdates = true;
      }
    }

    for (var s in sales) processBillItems(s.items);
    for (var sc in saleChallans) processBillItems(sc.items);
    for (var sr in saleReturns) processBillItems(sr.items);

    for (var p in purchases) processPurchaseItems(p.items);
    for (var pc in purchaseChallans) processPurchaseItems(pc.items);
    for (var pr in purchaseReturns) processPurchaseItems(pr.items);

    if (hasUpdates) {
      save();
      notifyListeners();
    }
  }

  void runAutoShortageScan() { shortages.removeWhere((s) => s.source == "Auto"); for (var m in medicines) { double a = calculateAvgMonthlySale(m.id); double r = a * 1.5; if (m.stock < r && r > 0) { shortages.add(ShortageItem(id: "auto_${m.id}", medicineId: m.id, medicineName: m.name, companyName: m.companyId, qtyRequired: r - m.stock, currentStock: m.stock, date: DateTime.now(), source: "Auto")); } } save(); }
 // ===========================================================================
  // 📈 INTELLIGENT SHORTAGE ENGINE (NET-SALE FORMULA)
  // ===========================================================================
  double calculateAvgMonthlySale(String mid) {
    DateTime thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    double grossSaleQty = 0;
    double returnedQty = 0;

    for (var s in sales.where((s) => s.status == "Active" && s.date.isAfter(thirtyDaysAgo))) {
      for (var item in s.items.where((it) => it.medicineID == mid)) {
        grossSaleQty += (item.qty + item.freeQty);
      }
    }

    for (var r in saleReturns.where((r) => r.status == "Active" && r.date.isAfter(thirtyDaysAgo))) {
      for (var item in r.items.where((it) => it.medicineID == mid && it.isBreakage == false)) {
        returnedQty += (item.qty + item.freeQty);
      }
    }

    double netMonthlySale = grossSaleQty - returnedQty;
    return netMonthlySale < 0 ? 0 : netMonthlySale;
  }
  void adjustBatchStock({
    required String medId,
    required String batchNo,
    required double adjQty,
    required String reason,
    String adjustedBy = "User",
  }) {
    if (batchHistory.containsKey(medId)) {
      try {
        var b = batchHistory[medId]!.firstWhere((x) => x.batch == batchNo);
        double prev = b.qty;
        b.adjustmentQty += adjQty;
        b.adjReason = reason;
        b.version += 1;
        b.updatedAt = DateTime.now().millisecondsSinceEpoch;

        final rec = BatchAdjustmentRecord(
          id: "ADJ_${DateTime.now().millisecondsSinceEpoch}_${b.adjustmentHistory.length + 1}",
          timestamp: DateTime.now().millisecondsSinceEpoch,
          previousQty: prev,
          adjustmentQty: adjQty,
          newQty: prev + adjQty,
          reason: reason,
          adjustedBy: adjustedBy,
        );
        b.adjustmentHistory.add(rec);

        if (activeCompany != null && activeCompany!.id.isNotEmpty) {
          BatchSyncModule.onBatchSaved(
            batch: b,
            medIdentityKey: medId,
            storeToken: activeCompany!.id,
            isDelete: false,
          );
        }
        rebuildInventory();
        save().then((_) => loadAllData());
      } catch (e) {}
    }
  }

  void updateBatchMetadata({required String medId, required String batchNo, required String newExp, required double newMrp, required double newRate}) {
    if (batchHistory.containsKey(medId)) {
      try {
        var b = batchHistory[medId]!.firstWhere((x) => x.batch == batchNo);
        b.exp = newExp;
        b.mrp = newMrp;
        b.rate = newRate;
        b.version += 1;
        b.updatedAt = DateTime.now().millisecondsSinceEpoch;
        if (activeCompany != null && activeCompany!.id.isNotEmpty) {
          BatchSyncModule.onBatchSaved(
            batch: b,
            medIdentityKey: medId,
            storeToken: activeCompany!.id,
            isDelete: false,
          );
        }
        rebuildInventory();
        save().then((_) => loadAllData());
      } catch (e) {}
    }
  }
  
  // ===========================================================================
  // 💹 ADVANCED ACCOUNTING & VOUCHER ENGINE
  // ===========================================================================

  List<Map<String, dynamic>> getPendingBills(String partyId, bool isReceipt, {String? excludeVoucherId}) {
    List<Map<String, dynamic>> pending = [];
    DateTime now = DateTime.now();

    final activeVouchers = vouchers.where((v) {
      if (v.status != 'Active' || v.isDeleted != 0) return false;
      if (excludeVoucherId != null &&
          excludeVoucherId.isNotEmpty &&
          (v.id == excludeVoucherId || v.voucherNo == excludeVoucherId)) {
        return false;
      }
      return true;
    }).toList();

    if (isReceipt) {
      for (var s in sales.where((s) => s.partyId == partyId && s.paymentMode == "CREDIT" && s.status == "Active")) {
        double billTotal = s.totalAmount;
        double totalSettled = 0.0;
        for (var v in activeVouchers) {
          totalSettled += v.getAllocatedAmount(s.billNo);
        }
        if (totalSettled > billTotal) totalSettled = billTotal;
        double remainingDue = billTotal - totalSettled;
        remainingDue = double.parse(remainingDue.toStringAsFixed(2));

        if (remainingDue > 0.01) {
          int days = now.difference(s.date).inDays;
          pending.add({
            'date': s.date,
            'billNo': s.billNo,
            'amount': remainingDue,
            'totalAmount': billTotal,
            'paidAmount': totalSettled,
            'dueDays': days,
            'status': totalSettled > 0.01 ? 'PARTIAL' : 'UNSETTLED',
          });
        }
      }
    } else {
      for (var p in purchases.where((p) => p.partyId == partyId && p.paymentMode == "CREDIT")) {
        double billTotal = p.totalAmount;
        double totalSettled = 0.0;
        for (var v in activeVouchers) {
          totalSettled += v.getAllocatedAmount(p.billNo);
        }
        if (totalSettled > billTotal) totalSettled = billTotal;
        double remainingDue = billTotal - totalSettled;
        remainingDue = double.parse(remainingDue.toStringAsFixed(2));

        if (remainingDue > 0.01) {
          int days = now.difference(p.date).inDays;
          pending.add({
            'date': p.date,
            'billNo': p.billNo,
            'amount': remainingDue,
            'totalAmount': billTotal,
            'paidAmount': totalSettled,
            'dueDays': days,
            'status': totalSettled > 0.01 ? 'PARTIAL' : 'UNSETTLED',
          });
        }
      }
    }
    pending.sort((a, b) => a['date'].compareTo(b['date']));
    return pending;
  }
  
  List<BankTransaction> getBankStatement(String bankName, DateTime from, DateTime to) {
    return AppAccountsCalculator.getBankBookStatement(
      bankName: bankName,
      fromDate: from,
      toDate: to,
      sales: sales,
      purchases: purchases,
      vouchers: vouchers,
    );
  }

  List<Party> getInternalAccounts() {
    return parties.where((p) => 
      p.group == "Bank Accounts" || p.group == "Cash in Hand"
    ).toList();
  }

  String getLastUsedBank(String partyId) {
    try {
      final lastVoucher = vouchers.lastWhere((v) => v.partyId == partyId && v.bankName.isNotEmpty);
      return lastVoucher.bankName;
    } catch (e) { return ""; }
  }

  Future<String> finalizeVoucher(Voucher v) async {
    final String cleanVNo = v.voucherNo.trim().toUpperCase();
    int currentVer = v.version;
    final int existingIdx = vouchers.indexWhere((x) =>
      x.id == v.id || (cleanVNo.isNotEmpty && x.voucherNo.trim().toUpperCase() == cleanVNo)
    );
    if (existingIdx != -1) {
      final oldVer = vouchers[existingIdx].version;
      if (oldVer >= currentVer) {
        currentVer = oldVer + 1;
      }
    }
    final int knownVer = D1SalesLedgerService.getKnownVersion(v.id, cleanVNo);
    if (knownVer >= currentVer) {
      currentVer = knownVer + 1;
    }
    v.updatedAt = DateTime.now().millisecondsSinceEpoch;
    v.version = currentVer;
    v.isDeleted = 0;
    D1SalesLedgerService.unmarkPermanentlyDeleted(v.id, cleanVNo);
    D1SalesLedgerService.recordKnownVersion(v.id, cleanVNo, v.version);

    vouchers.removeWhere((x) =>
      x.id == v.id || (cleanVNo.isNotEmpty && x.voucherNo.trim().toUpperCase() == cleanVNo)
    );
    vouchers.add(v);
    notifyListeners();
    await save();

    if (activeCompany != null) {
      await TombstoneEngine.unmarkTombstoneWithTimestamp(
        activeCompany!.id,
        id: v.id,
        secondaryKey: cleanVNo,
      );
      final String t = await WebLiveToken.getOrCreateToken(activeCompany!.id);
      if (t.isNotEmpty) {
        WebVoucherD1SyncService.onVoucherSaved(v, t, clientSource: "MOBILE_APP");
      }
      String seriesType = v.type.toUpperCase();
      String prefix = v.voucherNo.split(RegExp(r'\d')).first;
      await PharoahNumberingEngine.updateSeriesCounter(
        type: seriesType,
        companyID: activeCompany!.id,
        usedNumber: v.voucherNo,
        prefix: prefix,
      );
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: 'VOUCHER_SAVED',
        entityId: v.id,
        unmarkedIds: [v.id, if (cleanVNo.isNotEmpty) cleanVNo],
      );
    }
    return v.id;
  }

  bool isCashLimitExceeded(String partyId, double newAmount) {
    DateTime today = DateTime.now();
    double todayTotal = vouchers
        .where((v) => v.partyId == partyId && v.paymentMode == "Cash" && 
                v.date.day == today.day && v.date.month == today.month)
        .fold(0, (sum, v) => sum + v.amount);
    return (todayTotal + newAmount) > 200000;
  }

  // ===========================================================================
  // 8. MASTERS CRUD (ADD/UPDATE/DELETE)
  // ===========================================================================

  String resolveCompanyName(String idOrName) => MasterCascadeService.resolveCompanyName(idOrName, companies);
  String resolveSaltName(String idOrName) => MasterCascadeService.resolveSaltName(idOrName, salts);

  String getOrCreateCompany(String n) {
    final cleanTarget = CompanySyncModule.cleanString(n);
    if (cleanTarget.isEmpty) return "";
    try {
      return companies.firstWhere((c) => CompanySyncModule.cleanString(c.name) == cleanTarget || c.id.trim().toUpperCase() == n.trim().toUpperCase()).id;
    } catch (_) {
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      String id = "CP-${1000 + companies.length + 1}-${nowTs % 10000}";
      final newComp = Company(id: id, name: n.trim().toUpperCase(), updatedAt: nowTs, version: 1);
      saveOrUpdateCompany(newComp);
      return id;
    }
  }

  String getOrCreateSalt(String n) {
    final cleanTarget = SaltSyncModule.cleanString(n);
    if (cleanTarget.isEmpty) return "";
    try {
      return salts.firstWhere((s) => SaltSyncModule.cleanString(s.name) == cleanTarget || s.id.trim().toUpperCase() == n.trim().toUpperCase()).id;
    } catch (_) {
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      String id = "SL-${1000 + salts.length + 1}-${nowTs % 10000}";
      final newSalt = Salt(id: id, name: n.trim().toUpperCase(), type: "Mono", updatedAt: nowTs, version: 1);
      saveOrUpdateSalt(newSalt);
      return id;
    }
  }

  String getOrCreateRoute(String n) {
    final cleanTarget = RouteSyncModule.cleanString(n);
    if (cleanTarget.isEmpty) return "";
    try {
      return routes.firstWhere((r) => RouteSyncModule.cleanString(r.name) == cleanTarget || r.id.trim().toUpperCase() == n.trim().toUpperCase()).name;
    } catch (_) {
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      String id = "RT-${1000 + routes.length + 1}-${nowTs % 10000}";
      final newRoute = RouteArea(id: id, name: n.trim().toUpperCase(), updatedAt: nowTs, version: 1);
      saveOrUpdateRoute(newRoute);
      return newRoute.name;
    }
  }

  
  void addSalesman(Salesman s) { salesmen.add(s); save(); notifyListeners(); }
  void deleteSalesman(String id) { salesmen.removeWhere((s) => s.id == id); save(); notifyListeners(); }

  void addMedicine(Medicine m, {bool doSave = true}) {
    saveOrUpdateMedicine(m);
  }

  void saveOrUpdateMedicine(Medicine med) {
    final String cleanKey = MedicineSyncModule.getCompositeKey(name: med.name, packing: med.packing, company: med.companyId);
    final int nowTs = DateTime.now().millisecondsSinceEpoch;

    int existingIdx = medicines.indexWhere((m) {
      if (med.id.isNotEmpty && m.id == med.id) return true;
      if (med.systemId.isNotEmpty && m.systemId.trim().toUpperCase() == med.systemId.trim().toUpperCase()) return true;
      if (cleanKey.isNotEmpty && MedicineSyncModule.getCompositeKey(name: m.name, packing: m.packing, company: m.companyId) == cleanKey) {
        return true;
      }
      return false;
    });

    if (existingIdx != -1) {
      final old = medicines[existingIdx];
      med.id = old.id;
      if (med.systemId.isEmpty) med.systemId = old.systemId;
      med.version = old.version + 1;
      med.updatedAt = nowTs;
      medicines[existingIdx] = med;
    } else {
      if (med.id.isEmpty || med.id == '0' || med.id == 'temp') {
        med.id = "MED-$nowTs";
      }
      med.updatedAt = nowTs;
      if (med.version < 1) med.version = 1;
      medicines.add(med);
    }

    if (!batchHistory.containsKey(med.identityKey)) {
      batchHistory[med.identityKey] = [];
    }

    save();
    notifyListeners();

    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          MedicineSyncModule.onMedicineSaved(med, t);
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: 'MEDICINE_SAVED',
        entityId: med.id,
      );
    }
  }

  bool deleteMedicine(String medId) {
    Medicine? target;
    try {
      target = medicines.firstWhere((m) => m.id == medId || (m.systemId.isNotEmpty && m.systemId == medId));
    } catch (_) {}

    if (target != null) {
      final check = canDeleteMedicine(target);
      if (!check.canDelete) {
        return false;
      }
      final compKey = MedicineSyncModule.getCompositeKey(name: target.name, packing: target.packing, company: target.companyId);
      D1SalesLedgerService.markPermanentlyDeleted(medId, target.systemId, compKey);
      if (activeCompany != null) {
        TombstoneEngine.recordBatchTombstones(activeCompany!.id, [medId, if (target.systemId.isNotEmpty) target.systemId]);
      }
      medicines.removeWhere((m) => m.id == medId);
      save();
      notifyListeners();

      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) {
            MedicineSyncModule.onMedicineSaved(target!, t, isDelete: true);
          }
        });
        AppRealtimeCoordinator.instance.notifyAppMutation(
          this,
          action: 'MEDICINE_DELETED',
          entityId: medId,
          deletedIds: [medId],
        );
      }
      return true;
    }
    return false;
  }
  void addRoute(RouteArea r) => saveOrUpdateRoute(r);
  void addCompany(Company c) => saveOrUpdateCompany(c);
  void addSalt(Salt s) => saveOrUpdateSalt(s);

  void saveOrUpdateCompany(Company comp, {String? previousName}) {
    final nowTs = DateTime.now().millisecondsSinceEpoch;
    final cleanName = comp.name.trim().toUpperCase();
    final cleanKey = CompanySyncModule.cleanString(cleanName);
    if (cleanKey.isEmpty) return;

    int idx = companies.indexWhere((c) =>
        (comp.id.isNotEmpty && c.id.trim().toUpperCase() == comp.id.trim().toUpperCase()) ||
        CompanySyncModule.cleanString(c.name) == cleanKey);

    String? oldName = previousName;
    late Company savedComp;

    if (idx != -1) {
      final existing = companies[idx];
      oldName ??= existing.name;
      savedComp = Company(
        id: existing.id,
        name: cleanName,
        version: existing.version + 1,
        updatedAt: nowTs,
      );
      companies[idx] = savedComp;
    } else {
      final newId = (comp.id.trim().isEmpty || comp.id.contains(" "))
          ? "CP-${1000 + companies.length + 1}-${nowTs % 10000}"
          : comp.id.trim();
      savedComp = Company(
        id: newId,
        name: cleanName,
        version: comp.version > 0 ? comp.version : 1,
        updatedAt: nowTs,
      );
      companies.add(savedComp);
    }

    final cTombKey = "COMP_$cleanKey";
    D1SalesLedgerService.unmarkPermanentlyDeleted(savedComp.id, cTombKey);
    if (activeCompany != null) {
      TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: savedComp.id, secondaryKey: cTombKey);
    }

    final List<Medicine> mutatedMeds = [];
    MasterCascadeService.cascadeCompanyUpdate(
      updatedCompany: savedComp,
      previousName: oldName,
      medicines: medicines,
      shortages: shortages,
      onMedicineMutated: (m) => mutatedMeds.add(m),
    );

    save();
    notifyListeners();

    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          CompanySyncModule.onCompanySaved(savedComp, t, previousName: oldName);
          for (final m in mutatedMeds) {
            MedicineSyncModule.onMedicineSaved(m, t);
          }
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: "COMPANY_SAVED",
        entityId: savedComp.id,
        unmarkedIds: [savedComp.id, cTombKey],
      );
    }
  }

  bool deleteCompany(String id, {String? reassignToCompanyId}) {
    final idx = companies.indexWhere((c) => c.id == id);
    if (idx == -1) return false;
    final target = companies[idx];
    final cleanKey = "COMP_${CompanySyncModule.cleanString(target.name)}";
    final nowTs = DateTime.now().millisecondsSinceEpoch;

    final List<Medicine> mutatedMeds = [];
    for (var m in medicines) {
      if (MasterCascadeService.belongsToCompany(m, target)) {
        m.companyId = reassignToCompanyId ?? "";
        m.version += 1;
        m.updatedAt = nowTs;
        mutatedMeds.add(m);
      }
    }

    companies.removeAt(idx);
    D1SalesLedgerService.markPermanentlyDeleted(target.id, cleanKey);
    if (activeCompany != null) {
      TombstoneEngine.recordBatchTombstones(activeCompany!.id, [target.id, cleanKey]);
    }
    save();
    notifyListeners();

    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          CompanySyncModule.onCompanySaved(target, t, isDelete: true);
          for (final m in mutatedMeds) {
            MedicineSyncModule.onMedicineSaved(m, t);
          }
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: "COMPANY_DELETED",
        entityId: target.id,
        deletedIds: [target.id, cleanKey],
      );
    }
    return true;
  }

  void saveOrUpdateSalt(Salt salt, {String? previousName}) {
    final nowTs = DateTime.now().millisecondsSinceEpoch;
    final cleanName = salt.name.trim().toUpperCase();
    final cleanKey = SaltSyncModule.cleanString(cleanName);
    if (cleanKey.isEmpty) return;

    int idx = salts.indexWhere((s) =>
        (salt.id.isNotEmpty && s.id.trim().toUpperCase() == salt.id.trim().toUpperCase()) ||
        SaltSyncModule.cleanString(s.name) == cleanKey);

    String? oldName = previousName;
    late Salt savedSalt;

    if (idx != -1) {
      final existing = salts[idx];
      oldName ??= existing.name;
      savedSalt = Salt(
        id: existing.id,
        name: cleanName,
        type: salt.type.isNotEmpty ? salt.type : existing.type,
        version: existing.version + 1,
        updatedAt: nowTs,
      );
      salts[idx] = savedSalt;
    } else {
      final newId = (salt.id.trim().isEmpty || salt.id.contains(" "))
          ? "SL-${1000 + salts.length + 1}-${nowTs % 10000}"
          : salt.id.trim();
      savedSalt = Salt(
        id: newId,
        name: cleanName,
        type: salt.type.isNotEmpty ? salt.type : "Mono",
        version: salt.version > 0 ? salt.version : 1,
        updatedAt: nowTs,
      );
      salts.add(savedSalt);
    }

    final sTombKey = "SALT_$cleanKey";
    D1SalesLedgerService.unmarkPermanentlyDeleted(savedSalt.id, sTombKey);
    if (activeCompany != null) {
      TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: savedSalt.id, secondaryKey: sTombKey);
    }

    final List<Medicine> mutatedMeds = [];
    MasterCascadeService.cascadeSaltUpdate(
      updatedSalt: savedSalt,
      previousName: oldName,
      medicines: medicines,
      onMedicineMutated: (m) => mutatedMeds.add(m),
    );

    save();
    notifyListeners();

    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          SaltSyncModule.onSaltSaved(savedSalt, t, previousName: oldName);
          for (final m in mutatedMeds) {
            MedicineSyncModule.onMedicineSaved(m, t);
          }
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: "SALT_SAVED",
        entityId: savedSalt.id,
        unmarkedIds: [savedSalt.id, sTombKey],
      );
    }
  }

  bool deleteSalt(String id, {String? reassignToSaltId}) {
    final idx = salts.indexWhere((s) => s.id == id);
    if (idx == -1) return false;
    final target = salts[idx];
    final cleanKey = "SALT_${SaltSyncModule.cleanString(target.name)}";
    final nowTs = DateTime.now().millisecondsSinceEpoch;

    final List<Medicine> mutatedMeds = [];
    for (var m in medicines) {
      if (MasterCascadeService.belongsToSalt(m, target)) {
        m.saltId = reassignToSaltId ?? "";
        m.version += 1;
        m.updatedAt = nowTs;
        mutatedMeds.add(m);
      }
    }

    salts.removeAt(idx);
    D1SalesLedgerService.markPermanentlyDeleted(target.id, cleanKey);
    if (activeCompany != null) {
      TombstoneEngine.recordBatchTombstones(activeCompany!.id, [target.id, cleanKey]);
    }
    save();
    notifyListeners();

    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          SaltSyncModule.onSaltSaved(target, t, isDelete: true);
          for (final m in mutatedMeds) {
            MedicineSyncModule.onMedicineSaved(m, t);
          }
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: "SALT_DELETED",
        entityId: target.id,
        deletedIds: [target.id, cleanKey],
      );
    }
    return true;
  }

  void saveOrUpdateRoute(RouteArea route, {String? previousName}) {
    final nowTs = DateTime.now().millisecondsSinceEpoch;
    final cleanName = route.name.trim().toUpperCase();
    final cleanKey = RouteSyncModule.cleanString(cleanName);
    if (cleanKey.isEmpty) return;

    int idx = routes.indexWhere((r) =>
        (route.id.isNotEmpty && r.id.trim().toUpperCase() == route.id.trim().toUpperCase()) ||
        RouteSyncModule.cleanString(r.name) == cleanKey);

    String? oldName = previousName;
    late RouteArea savedRoute;

    if (idx != -1) {
      final existing = routes[idx];
      oldName ??= existing.name;
      savedRoute = RouteArea(
        id: existing.id,
        name: cleanName,
        version: existing.version + 1,
        updatedAt: nowTs,
      );
      routes[idx] = savedRoute;
    } else {
      final newId = (route.id.trim().isEmpty || route.id.contains(" "))
          ? "RT-${1000 + routes.length + 1}-${nowTs % 10000}"
          : route.id.trim();
      savedRoute = RouteArea(
        id: newId,
        name: cleanName,
        version: route.version > 0 ? route.version : 1,
        updatedAt: nowTs,
      );
      routes.add(savedRoute);
    }

    final rTombKey = "ROUTE_$cleanKey";
    D1SalesLedgerService.unmarkPermanentlyDeleted(savedRoute.id, rTombKey);
    if (activeCompany != null) {
      TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: savedRoute.id, secondaryKey: rTombKey);
    }

    final List<Party> mutatedParties = [];
    MasterCascadeService.cascadeRouteUpdate(
      updatedRoute: savedRoute,
      previousName: oldName,
      parties: parties,
      onPartyMutated: (p) => mutatedParties.add(p),
    );

    save();
    notifyListeners();

    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          RouteSyncModule.onRouteSaved(savedRoute, t, previousName: oldName);
          for (final p in mutatedParties) {
            PartySyncModule.onPartySaved(p, t);
          }
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: "ROUTE_SAVED",
        entityId: savedRoute.id,
        unmarkedIds: [savedRoute.id, rTombKey],
      );
    }
  }
  
  void createGstDiarySession(GstDiarySession s) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    s.version = s.version <= 0 ? 1 : s.version;
    s.updatedAt = now;
    s.isDeleted = 0;
    gstDiarySessions.removeWhere((x) => x.id == s.id);
    gstDiarySessions.insert(0, s);
    save();
    notifyListeners();
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          GstDiaryD1SyncService.onSessionSaved(s, t, clientSource: "MOBILE_APP");
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: "GST_SESSION_SAVED",
        entityId: s.id,
        unmarkedIds: [s.id],
      );
    }
  }

  void updateGstDiarySession(GstDiarySession s) {
    int i = gstDiarySessions.indexWhere((x) => x.id == s.id);
    if (i != -1) {
      s.version = gstDiarySessions[i].version + 1;
      s.updatedAt = DateTime.now().millisecondsSinceEpoch;
      s.isDeleted = 0;
      gstDiarySessions[i] = s;
      save();
      notifyListeners();
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) {
            GstDiaryD1SyncService.onSessionSaved(s, t, clientSource: "MOBILE_APP");
          }
        });
        AppRealtimeCoordinator.instance.notifyAppMutation(
          this,
          action: "GST_SESSION_UPDATED",
          entityId: s.id,
          unmarkedIds: [s.id],
        );
      }
    }
  }

  void deleteGstDiarySession(String id) {
    String title = "";
    try {
      title = gstDiarySessions.firstWhere((x) => x.id == id).title;
    } catch (_) {}
    gstDiarySessions.removeWhere((x) => x.id == id);
    D1SalesLedgerService.markPermanentlyDeleted(id, title);
    if (activeCompany != null) {
      TombstoneEngine.recordBatchTombstones(activeCompany!.id, [id]);
    }
    save();
    notifyListeners();
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          GstDiaryD1SyncService.onSessionDeleted(id, t, sessionTitle: title, clientSource: "MOBILE_APP");
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: "DELETE_GST_SESSION",
        entityId: id,
        deletedIds: [id],
      );
    }
  }

  void addDrugType(DrugType d) { drugTypes.add(d); save(); }
  void addSystemUser(SystemUser u) { systemUsers.add(u); save(); }
  void addNumberingSeries(NumberingSeries ns) { numberingSeries.add(ns); save(); }
  void addBank(Bank b) { banks.add(b); save(); }
  void addCheque(ChequeEntry c) { cheques.add(c); save(); }
  void addLog(String a, String d) { logs.add(LogEntry(id: DateTime.now().toString(), action: a, details: d, time: DateTime.now())); save(); }
  void addManualShortage({required Medicine med, required double qty, String cust = ""}) { shortages.add(ShortageItem(id: DateTime.now().toString(), medicineId: med.id, medicineName: med.name, companyName: med.companyId, qtyRequired: qty, currentStock: med.stock, date: DateTime.now(), customerName: cust)); save(); }
  
  void _reverseVoucherImpact(Voucher v) {
    addLog("ACCOUNTS", "Reversed Impact of ${v.voucherNo} for ${v.partyName}");
  }

  Future<void> cancelVoucher(String id) async {
    int i = vouchers.indexWhere((v) => v.id == id || v.voucherNo == id);
    if (i != -1) {
      final v = vouchers[i];
      final String cleanVNo = v.voucherNo.trim().toUpperCase();
      _reverseVoucherImpact(v);

      int nextVer = v.version + 1;
      final int knownVer = D1SalesLedgerService.getKnownVersion(v.id, cleanVNo);
      if (knownVer >= nextVer) {
        nextVer = knownVer + 1;
      }

      for (int idx = 0; idx < vouchers.length; idx++) {
        if (vouchers[idx].id == v.id || (cleanVNo.isNotEmpty && vouchers[idx].voucherNo.trim().toUpperCase() == cleanVNo)) {
          vouchers[idx].status = "Cancelled";
          vouchers[idx].isDeleted = 0;
          if (!vouchers[idx].narration.startsWith("[CANCELLED]")) {
            vouchers[idx].narration = "[CANCELLED] ${vouchers[idx].narration}".trim();
          }
          vouchers[idx].version = nextVer;
          vouchers[idx].updatedAt = DateTime.now().millisecondsSinceEpoch;
        }
      }

      D1SalesLedgerService.unmarkPermanentlyDeleted(v.id, cleanVNo);
      D1SalesLedgerService.recordKnownVersion(v.id, cleanVNo, v.version);

      // Immediate 0ms UI update on first tap
      notifyListeners();
      await save();

      if (activeCompany != null) {
        await TombstoneEngine.unmarkTombstoneWithTimestamp(
          activeCompany!.id,
          id: v.id,
          secondaryKey: cleanVNo,
        );
        final String t = await WebLiveToken.getOrCreateToken(activeCompany!.id);
        if (t.isNotEmpty) {
          WebVoucherD1SyncService.onVoucherCancelled(v, t, clientSource: "MOBILE_APP");
        }
        AppRealtimeCoordinator.instance.notifyAppMutation(
          this,
          action: 'CANCEL_VOUCHER',
          entityId: v.id,
          unmarkedIds: [v.id, if (cleanVNo.isNotEmpty) cleanVNo],
        );
      }
    }
  }

  Future<void> deleteVoucher(String id) async {
    int i = vouchers.indexWhere((v) => v.id == id || v.voucherNo == id);
    if (i != -1) {
      final v = vouchers[i];
      final String realId = v.id;
      final String vNo = v.voucherNo.trim().toUpperCase();
      _reverseVoucherImpact(v);

      // 1. Synchronous memory & D1 gravestone lock + immediate 0ms UI removal on 1st tap
      D1SalesLedgerService.markPermanentlyDeleted(realId, vNo);
      D1SalesLedgerService.recordKnownVersion(realId, vNo, 999999);
      vouchers.removeWhere((x) =>
        x.id == realId ||
        x.id == id ||
        (vNo.isNotEmpty && x.voucherNo.trim().toUpperCase() == vNo)
      );
      notifyListeners();

      // 2. Persist disk & SharedPreferences tombstones BEFORE triggering cloud sync so it can NEVER resurrect
      final List<String> delKeys = [
        realId,
        if (id != realId) id,
        if (vNo.isNotEmpty) vNo,
      ];
      if (activeCompany != null) {
        await TombstoneEngine.recordBatchTombstones(activeCompany!.id, delKeys);
      }
      await save();

      if (activeCompany != null) {
        final String t = await WebLiveToken.getOrCreateToken(activeCompany!.id);
        if (t.isNotEmpty) {
          WebVoucherD1SyncService.onVoucherDeleted(v, t, clientSource: "MOBILE_APP");
        }
        AppRealtimeCoordinator.instance.notifyAppMutation(
          this,
          action: 'DELETE_VOUCHER',
          entityId: realId,
          deletedIds: delKeys,
        );
      }
    }
  }

  // ===========================================================================
  // ⚡ ADVANCED STOCK-SAFE MODIFICATION ENGINE
  // ===========================================================================

  Future<void> updateSaleReturn({required String id, required String billNo, required DateTime date, required Party party, required List<BillItem> items, required double total, double extraDiscount = 0.0, double roundOff = 0.0}) async {
    int i = saleReturns.indexWhere((r) => r.id == id);
    if (i != -1) {
      final oldVer = saleReturns[i].version;
      final updatedReturn = SaleReturn(
        id: id, billNo: billNo, date: date, partyName: party.name, 
        items: items, totalAmount: total, extraDiscount: extraDiscount, 
        roundOff: roundOff, status: "Active",
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        version: oldVer + 1,
      );
      saleReturns[i] = updatedReturn;
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) ReturnsSyncModule.onSaleReturnSaved(updatedReturn, t);
        });
      }
      
      await save(); 
      InventoryLogicCenter.rebuildAllInventory(
        medicines: medicines, batchHistory: batchHistory, 
        purchases: purchases, sales: sales, 
        saleReturns: saleReturns, purchaseReturns: purchaseReturns
      );
      notifyListeners();
    }
  }

  Future<void> updatePurchaseReturn({required String id, required String billNo, required DateTime date, required Party party, required List<PurchaseItem> items, required double total, double extraDiscount = 0.0, double roundOff = 0.0}) async {
    int i = purchaseReturns.indexWhere((r) => r.id == id);
    if (i != -1) {
      final oldVer = purchaseReturns[i].version;
      final updatedPReturn = PurchaseReturn(
        id: id, billNo: billNo, distributorName: party.name, 
        date: date, items: items, totalAmount: total, 
        extraDiscount: extraDiscount, roundOff: roundOff, status: "Active",
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        version: oldVer + 1,
      );
      purchaseReturns[i] = updatedPReturn;
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) DebitNoteSyncModule.onDebitNoteSaved(updatedPReturn, t);
        });
      }

      await save();
      InventoryLogicCenter.rebuildAllInventory(
        medicines: medicines, batchHistory: batchHistory, 
        purchases: purchases, sales: sales, 
        saleReturns: saleReturns, purchaseReturns: purchaseReturns
      );
      notifyListeners();
    }
  }

  void updateSystemUser(SystemUser u) { int i = systemUsers.indexWhere((x) => x.id == u.id); if(i != -1) { systemUsers[i] = u; save(); } }
  void updateNumberingSeries(NumberingSeries ns) { int i = numberingSeries.indexWhere((x) => x.id == ns.id); if(i != -1) { numberingSeries[i] = ns; save(); } }
  void updateAppConfig(AppConfig c) {
    c.version += 1;
    c.updatedAt = DateTime.now().millisecondsSinceEpoch;
    config = c;
    save();
    notifyListeners();
    if (activeCompany != null && activeCompany!.id.isNotEmpty) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          SyncQueueManager.enqueueMutation(
            syncId: 'APP_CONFIG_MASTER',
            storeToken: t.trim().toUpperCase(),
            docType: 'CONFIG',
            currentVersion: c.version,
            isDelete: false,
            rawPayload: c.toMap(),
          );
          GstDiaryD1SyncService.onAppConfigSaved(c, t, clientSource: "MOBILE_APP");
        }
      });
    }
    AppRealtimeCoordinator.instance.notifyAppMutation(
      this,
      action: 'CONFIG_UPDATED',
      entityId: 'APP_CONFIG_MASTER',
    );
  }
  void updateChequeStatus(String id, String s, String r) { int i = cheques.indexWhere((c) => c.id == id); if(i != -1) { cheques[i].status = s; cheques[i].remark = r; save(); } }
  
  void cancelReturn(String id, bool isSaleReturn) {
    if (isSaleReturn) {
      int i = saleReturns.indexWhere((r) => r.id == id);
      if (i != -1) saleReturns[i].status = "Cancelled";
    } else {
      int i = purchaseReturns.indexWhere((r) => r.id == id);
      if (i != -1) purchaseReturns[i].status = "Cancelled";
    }
    save().then((_) => loadAllData());
  }

  
  void cancelBill(String id) {
    int i = sales.indexWhere((x) => x.id == id);
    if (i != -1) {
      sales[i].status = "Cancelled";
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) {
            D1SalesLedgerService.onSaleCancelled(sales[i], t, clientSource: "APP_MOBILE");
          }
        });
      }
      save().then((_) => loadAllData());
      notifyListeners();
    }
  }

  void deleteBill(String id) {
    try {
      final s = sales.firstWhere((x) => x.id == id || x.billNo == id);
      final List<String> revertedChallanIds = [];
      final List<String> revertedChallanBillNos = [];

      if (s.linkedChallanIds.isNotEmpty) {
        for (var cid in s.linkedChallanIds) {
          int i = saleChallans.indexWhere((c) => c.id == cid || c.billNo == cid);
          if (i != -1) {
            saleChallans[i].status = "Pending";
            saleChallans[i].version += 1;
            saleChallans[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
            revertedChallanIds.add(saleChallans[i].id);
            if (saleChallans[i].billNo.isNotEmpty) {
              revertedChallanBillNos.add(saleChallans[i].billNo);
            }
            D1SalesLedgerService.unmarkPermanentlyDeleted(saleChallans[i].id, saleChallans[i].billNo);
            if (activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: saleChallans[i].id, secondaryKey: saleChallans[i].billNo);
            }
            if (activeCompany != null) {
              WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
                if (t.isNotEmpty) SaleChallanSyncModule.onSaleChallanSaved(saleChallans[i], t);
              });
            }
          }
        }
      }
      final String realId = s.id;
      sales.removeWhere((x) => x.id == realId || (s.billNo.isNotEmpty && x.billNo.trim().toUpperCase() == s.billNo.trim().toUpperCase()));
      D1SalesLedgerService.markPermanentlyDeleted(realId, s.billNo);
      try {
        getWorkingPath().then((dir) {
          if (dir.isNotEmpty) {
            File('$dir/sales.json').writeAsStringSync(jsonEncode(sales.map((e) => e.toMap()).toList()));
            if (revertedChallanIds.isNotEmpty) {
              File('$dir/s_challan.json').writeAsStringSync(jsonEncode(saleChallans.map((e) => e.toMap()).toList()));
            }
          }
        });
      } catch (_) {}
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) {
            SalesSyncModule.onSaleDeleted(s, t);
            D1SalesLedgerService.onSaleDeleted(realId, s.billNo, t, clientSource: "APP_MOBILE", linkedChallanIds: s.linkedChallanIds);
            SyncQueueManager.flushOutboxAsJSONBatch();
          }
        });
      }
      if (activeCompany != null) {
        TombstoneEngine.recordTombstoneWithTimestamp(activeCompany!.id, id: realId, secondaryKey: s.billNo);
        final List<String> allUnmarked = [...revertedChallanIds, ...revertedChallanBillNos];
        AppRealtimeCoordinator.instance.notifyAppMutation(
          this,
          action: 'DELETE_SALE',
          entityId: realId,
          deletedIds: [realId, if (s.billNo.isNotEmpty) s.billNo],
          unmarkedIds: allUnmarked,
        );
      }
      save();
      notifyListeners();
    } catch (e) {}
  }
  void deletePurchase(String id) {
    try {
      final p = purchases.firstWhere((x) => x.id == id || x.internalNo == id || x.billNo == id);
      final List<String> revertedPChallanIds = [];
      final List<String> revertedPChallanNos = [];

      if (p.linkedChallanIds.isNotEmpty) {
        for (var cid in p.linkedChallanIds) {
          int i = purchaseChallans.indexWhere((c) => c.id == cid || c.internalNo == cid || c.billNo == cid);
          if (i != -1) {
            purchaseChallans[i].status = "Pending";
            purchaseChallans[i].version += 1;
            purchaseChallans[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
            revertedPChallanIds.add(purchaseChallans[i].id);
            if (purchaseChallans[i].internalNo.isNotEmpty) revertedPChallanNos.add(purchaseChallans[i].internalNo);
            if (purchaseChallans[i].billNo.isNotEmpty) revertedPChallanNos.add(purchaseChallans[i].billNo);
            D1SalesLedgerService.unmarkPermanentlyDeleted(purchaseChallans[i].id, purchaseChallans[i].billNo, purchaseChallans[i].internalNo);
            if (activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(activeCompany!.id, id: purchaseChallans[i].id, secondaryKey: purchaseChallans[i].internalNo);
            }
            if (activeCompany != null) {
              WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
                if (t.isNotEmpty) PurchaseChallanSyncModule.onPurchaseChallanSaved(purchaseChallans[i], t);
              });
            }
          }
        }
      }
      final String pId = p.id;
      final String intNo = p.internalNo.trim().toUpperCase();
      final String bNo = p.billNo.trim().toUpperCase();
      final String partyId = p.partyId.trim().toUpperCase();
      final String compKey2 = (partyId.isNotEmpty && bNo.isNotEmpty) ? "${partyId}_$bNo" : "";
      final String compKey3 = PurchaseSyncModule.makeCompositeKey(partyId, bNo, intNo);
      purchases.removeWhere((x) => 
        x.id == pId || 
        (intNo.isNotEmpty && x.internalNo.trim().toUpperCase() == intNo) ||
        (bNo.isNotEmpty && partyId.isNotEmpty && 
         x.billNo.trim().toUpperCase() == bNo && x.partyId.trim().toUpperCase() == partyId)
      );
      D1SalesLedgerService.markPurchasePermanentlyDeleted(pId, partyId, bNo, intNo);
      try {
        getWorkingPath().then((dir) {
          if (dir.isNotEmpty) {
            File('$dir/purc.json').writeAsStringSync(jsonEncode(purchases.map((e) => e.toMap()).toList()));
            if (revertedPChallanIds.isNotEmpty) {
              File('$dir/p_challan.json').writeAsStringSync(jsonEncode(purchaseChallans.map((e) => e.toMap()).toList()));
            }
          }
        });
      } catch (_) {}
      final List<String> delKeys = [
        pId,
        if (intNo.isNotEmpty) intNo,
        if (compKey2.isNotEmpty) compKey2,
        if (compKey3.isNotEmpty) compKey3,
      ];
      final List<String> allUnmarked = [...revertedPChallanIds, ...revertedPChallanNos];
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) {
            PurchaseSyncModule.onPurchaseDeleted(p, t);
            D1SalesLedgerService.onPurchaseDeleted(pId, partyId, bNo, intNo, t, clientSource: "APP_MOBILE", linkedChallanIds: p.linkedChallanIds);
            SyncQueueManager.flushOutboxAsJSONBatch();
          }
        });
        TombstoneEngine.recordBatchTombstones(activeCompany!.id, delKeys).then((_) {
          AppRealtimeCoordinator.instance.notifyAppMutation(
            this,
            action: 'DELETE_PURCHASE',
            entityId: pId,
            deletedIds: delKeys,
            unmarkedIds: allUnmarked,
          );
        });
      }
      InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns);
      save();
      notifyListeners();
    } catch (e) {}
  }
  void deleteSaleChallan(String id) {
    try {
      final c = saleChallans.firstWhere((x) => x.id == id || x.billNo == id);
      final cId = c.id;
      final bNo = c.billNo.trim().toUpperCase();
      final List<String> delKeys = [cId, if (bNo.isNotEmpty) bNo];
      D1SalesLedgerService.markPermanentlyDeleted(cId, bNo);
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) SaleChallanSyncModule.onSaleChallanDeleted(c, t);
        });
        TombstoneEngine.recordBatchTombstones(activeCompany!.id, delKeys);
        AppRealtimeCoordinator.instance.notifyAppMutation(
          this,
          action: 'DELETE_SALE_CHALLAN',
          entityId: cId,
          deletedIds: delKeys,
        );
        }
      saleChallans.removeWhere((x) => x.id == cId || (bNo.isNotEmpty && x.billNo.trim().toUpperCase() == bNo));
      save();
      notifyListeners();
    } catch (_) {
      saleChallans.removeWhere((c) => c.id == id);
      save();
      notifyListeners();
    }
  }
  void deletePurchaseChallan(String id) {
    try {
      final c = purchaseChallans.firstWhere((x) => x.id == id || x.internalNo == id || x.billNo == id);
      final cId = c.id;
      final iNo = c.internalNo.trim().toUpperCase();
      final bNo = c.billNo.trim().toUpperCase();
      final pId = c.partyId.trim().toUpperCase();
      final compKey2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
      final compKey3 = PurchaseChallanSyncModule.makeCompositeKey(pId, bNo, iNo);
      final List<String> delKeys = [
        cId,
        if (iNo.isNotEmpty) iNo,
        if (compKey2.isNotEmpty) compKey2,
        if (compKey3.isNotEmpty) compKey3,
      ];
      D1SalesLedgerService.markPurchasePermanentlyDeleted(cId, pId, bNo, iNo);

      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) PurchaseChallanSyncModule.onPurchaseChallanDeleted(c, t);
        });
        TombstoneEngine.recordBatchTombstones(activeCompany!.id, delKeys);
        AppRealtimeCoordinator.instance.notifyAppMutation(
          this,
          action: 'DELETE_PURCHASE_CHALLAN',
          entityId: cId,
          deletedIds: delKeys,
        );
      }
      purchaseChallans.removeWhere((x) =>
        x.id == cId ||
        (iNo.isNotEmpty && x.internalNo.trim().toUpperCase() == iNo) ||
        (pId.isNotEmpty && bNo.isNotEmpty && x.partyId.trim().toUpperCase() == pId && x.billNo.trim().toUpperCase() == bNo)
      );
      save();
      notifyListeners();
    } catch (_) {
      purchaseChallans.removeWhere((c) => c.id == id);
      save();
      notifyListeners();
    }
  }
  void deleteSaleReturn(String id) {
    try {
      final r = saleReturns.firstWhere((x) => x.id == id || x.billNo == id);
      final rId = r.id;
      final bNo = r.billNo.trim().toUpperCase();
      final List<String> delKeys = [rId, if (bNo.isNotEmpty) bNo];
      D1SalesLedgerService.markPermanentlyDeleted(rId, bNo);
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) CreditNoteSyncModule.onCreditNoteDeleted(r, t);
        });
        TombstoneEngine.recordBatchTombstones(activeCompany!.id, delKeys);
        AppRealtimeCoordinator.instance.notifyAppMutation(
          this,
          action: 'DELETE_SALE_RETURN',
          entityId: rId,
          deletedIds: delKeys,
        );
      }
      saleReturns.removeWhere((x) => x.id == rId || (bNo.isNotEmpty && x.billNo.trim().toUpperCase() == bNo));
      save().then((_) => loadAllData());
    } catch (_) {
      saleReturns.removeWhere((r) => r.id == id);
      save().then((_) => loadAllData());
    }
  }
  void deletePurchaseReturn(String id) {
    try {
      final r = purchaseReturns.firstWhere((x) => x.id == id || x.billNo == id);
      final rId = r.id;
      final bNo = r.billNo.trim().toUpperCase();
      final List<String> delKeys = [rId, if (bNo.isNotEmpty) bNo];
      D1SalesLedgerService.markPermanentlyDeleted(rId, bNo);
      if (activeCompany != null) {
        WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
          if (t.isNotEmpty) DebitNoteSyncModule.onDebitNoteDeleted(r, t);
        });
        TombstoneEngine.recordBatchTombstones(activeCompany!.id, delKeys);
        AppRealtimeCoordinator.instance.notifyAppMutation(
          this,
          action: 'DELETE_PURCHASE_RETURN',
          entityId: rId,
          deletedIds: delKeys,
        );
      }
      purchaseReturns.removeWhere((x) => x.id == rId || (bNo.isNotEmpty && x.billNo.trim().toUpperCase() == bNo));
      save().then((_) => loadAllData());
    } catch (_) {
      purchaseReturns.removeWhere((r) => r.id == id);
      save().then((_) => loadAllData());
    }
  }

  PartyDeleteCheckResult canDeleteParty(Party party) {
    return PartyIntegrityService.checkPartyDeletionEligibility(
      ph: this,
      party: party,
    );
  }

  bool deleteParty(String id) {
    try {
      final p = parties.firstWhere((pt) => pt.id == id);
      final check = canDeleteParty(p);
      if (check.canDelete) {
        parties.removeWhere((pt) => pt.id == id);
        D1SalesLedgerService.markPermanentlyDeleted(id, p.phone);
        save();
        notifyListeners();
        if (activeCompany != null) {
          WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
            if (t.isNotEmpty) {
              PartySyncModule.onPartySaved(p, t, isDelete: true);
            }
          });
          AppRealtimeCoordinator.instance.notifyAppMutation(
            this,
            action: 'PARTY_DELETED',
            entityId: id,
            deletedIds: [id],
          );
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  void saveOrUpdateParty(Party party) {
    PartySyncModule.registerPartyActivity(ph: this, updatedParty: party);
    MasterCascadeService.cascadePartyUpdate(
      updatedParty: party,
      sales: sales,
      purchases: purchases,
      saleChallans: saleChallans,
      purchaseChallans: purchaseChallans,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
      vouchers: vouchers,
    );
    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          PartySyncModule.onPartySaved(party, t);
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: 'PARTY_SAVED',
        entityId: party.id,
      );
    }
  }
  void deleteRoute(String id, {String? reassignToRouteName}) {
    final idx = routes.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    final target = routes[idx];
    final cleanKey = "ROUTE_${RouteSyncModule.cleanString(target.name)}";
    final nowTs = DateTime.now().millisecondsSinceEpoch;

    final List<Party> mutatedParties = [];
    for (var p in parties) {
      if (MasterCascadeService.belongsToRoute(p, target)) {
        p.route = reassignToRouteName?.trim().toUpperCase() ?? "";
        p.version += 1;
        p.updatedAt = nowTs;
        mutatedParties.add(p);
      }
    }

    routes.removeAt(idx);
    D1SalesLedgerService.markPermanentlyDeleted(target.id, cleanKey);
    if (activeCompany != null) {
      TombstoneEngine.recordBatchTombstones(activeCompany!.id, [target.id, cleanKey]);
    }
    save();
    notifyListeners();

    if (activeCompany != null) {
      WebLiveToken.getOrCreateToken(activeCompany!.id).then((t) {
        if (t.isNotEmpty) {
          RouteSyncModule.onRouteSaved(target, t, isDelete: true);
          for (final p in mutatedParties) {
            PartySyncModule.onPartySaved(p, t);
          }
        }
      });
      AppRealtimeCoordinator.instance.notifyAppMutation(
        this,
        action: "ROUTE_DELETED",
        entityId: target.id,
        deletedIds: [target.id, cleanKey],
      );
    }
  }
  void deleteSystemUser(String id) { systemUsers.removeWhere((x) => x.id == id); save(); }
  void deleteShortage(String id) { shortages.removeWhere((s) => s.id == id); save(); }
  void deleteBank(String id) { banks.removeWhere((b) => b.id == id); save(); }

  void resetCounter(String t) { if (activeCompany != null) { String pfx = (t == "SALE_BILL") ? "INV-" : (t == "PUR_BILL" ? "PUR-" : "SCH-"); PharoahNumberingEngine.resetSeries(type: t.contains("SALE") ? "SALE" : "PURCHASE", companyID: activeCompany!.id, prefix: pfx); } notifyListeners(); }

  // ===========================================================================
  // 9. DATA REGISTRY & YEAR-END
  // ===========================================================================

  Future<void> setupNewCompanyEnvironment(CompanyProfile p, String f) async { activeCompany = p; currentFY = f; numberingSeries = [NumberingSeries(id: 's1', name: "Standard Retail", type: "SALE", prefix: "INV-", isDefault: true)]; medicines = DemoData.getMedicines(); companies = MasterDataLibrary.getTopCompanies(); salts = MasterDataLibrary.getTopSalts(); drugTypes = MasterDataLibrary.getDrugTypes(); parties = [DemoData.getDemoParty(), Party(id: 'cash', name: "CASH", group: "Cash in Hand")]; await save(); if (!companiesRegistry.any((c) => c.id == p.id)) { companiesRegistry.add(p); await saveRegistry(); } notifyListeners(); }

  Future<Map<String, dynamic>> restoreCompanyFromCloud({
    required String storeToken,
    required String username,
    required String password,
  }) async {
    try {
      final res = await WebSyncEngine.fetchStoreData(
        storeToken: storeToken,
        username: username,
        password: password,
      );

      if (res["success"] != true) {
        return {
          "success": false,
          "message": res["message"] ?? "Failed to connect to Cloud Store.",
        };
      }

      final profileData = (res["profile"] is Map) ? (res["profile"] as Map<String, dynamic>) : <String, dynamic>{};
      final cleanToken = storeToken.trim().toUpperCase();
      final String compId = profileData["id"]?.toString() ?? "COMP-${cleanToken.replaceAll(RegExp(r"[^A-Za-z0-9]"), "")}";
      final String compName = profileData["name"]?.toString() ?? res["companyName"]?.toString() ?? "CLOUD STORE";
      final String bType = profileData["businessType"]?.toString() ?? "WHOLESALE";
      final Map<String, dynamic> rawCloudFilesForVault =
          (res["files"] is Map) ? Map<String, dynamic>.from(res["files"]) : {};
      final Map<String, Map<String, String>> cloudFyVault =
          MultiFyCloudVault.parseFyVault(rawCloudFilesForVault);

      final Set<String> discoveredFys = {};
      if (profileData["fYears"] is List) {
        for (final y in (profileData["fYears"] as List)) {
          final cy = y.toString().trim();
          if (cy.isNotEmpty) discoveredFys.add(cy);
        }
      }
      for (final vy in cloudFyVault.keys) {
        if (vy.trim().isNotEmpty) discoveredFys.add(vy.trim());
      }
      final String cloudTopFy = (res["fy"] != null && res["fy"].toString().trim().isNotEmpty)
          ? res["fy"].toString().trim()
          : AppDateLogic.getCurrentFYString();
      discoveredFys.add(cloudTopFy);

      final List<String> allFys = AppDateLogic.sortFYList(discoveredFys);
      final String fy = allFys.isNotEmpty ? allFys.last : cloudTopFy;

      final CompanyProfile restoredProfile = CompanyProfile(
        id: compId,
        name: compName,
        businessType: bType,
        createdAt: profileData["createdAt"] != null
            ? DateTime.tryParse(profileData["createdAt"].toString()) ?? DateTime.now()
            : DateTime.now(),
        address: profileData["address"]?.toString() ?? "",
        state: profileData["state"]?.toString() ?? "Rajasthan",
        gstin: profileData["gstin"]?.toString() ?? "N/A",
        dlNo: profileData["dlNo"]?.toString() ?? "N/A",
        phone: profileData["phone"]?.toString() ?? "",
        email: profileData["email"]?.toString() ?? "",
        adminUser: username.trim().toLowerCase(),
        password: password.trim(),
        isBiometricEnabled: profileData["isBiometricEnabled"] == true,
        recoveryKey: profileData["recoveryKey"]?.toString() ?? "",
        autoLockMinutes: (profileData["autoLockMinutes"] is int) ? profileData["autoLockMinutes"] : 5,
        fYears: allFys,
      );

      int existIdx = companiesRegistry.indexWhere((c) => c.id == restoredProfile.id);
      if (existIdx != -1) {
        companiesRegistry[existIdx] = restoredProfile;
      } else {
        companiesRegistry.add(restoredProfile);
      }
      await saveRegistry();

      await WebLiveToken.saveToken(cleanToken, companyId: restoredProfile.id);

      activeCompany = restoredProfile;
      currentFY = fy;
      isAdminAuthenticated = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_fy_${restoredProfile.id}', fy);
      await prefs.setString('last_active_fy_for_${restoredProfile.id}', fy);
      // Automatically activate Live Cloud & Web Sync upon Cloud Restore (no manual toggle required!)
      await prefs.setBool('is_live_web_active', true);
      await prefs.setBool('is_cloud_sync_paused_by_user', false);

      final rootDir = await getApplicationDocumentsDirectory();
      // 1. Unpack EVERY Financial Year from Multi-FY Cloud Vault onto local disk
      for (final vaultEntry in cloudFyVault.entries) {
        final String vFy = vaultEntry.key;
        final Directory fyDir = Directory("${rootDir.path}/Pharoah_Data/${restoredProfile.id}/${restoredProfile.businessType}/$vFy");
        if (!await fyDir.exists()) {
          await fyDir.create(recursive: true);
        }
        for (final fEntry in vaultEntry.value.entries) {
          if (fEntry.key == 'fy_vault.json') continue;
          await File("${fyDir.path}/${fEntry.key}").writeAsString(fEntry.value);
        }
      }

      // 2. Write active year downloaded files directly to canonical getWorkingPath() directory
      final workingDirPath = await getWorkingPath();
      final workingDir = Directory(workingDirPath);
      if (!await workingDir.exists()) {
        await workingDir.create(recursive: true);
      }

      final Map<String, dynamic> files = (res["files"] is Map) ? (res["files"] as Map<String, dynamic>) : {};
      final Map<String, String>? activeVaultFiles = cloudFyVault[fy];
      if (activeVaultFiles != null && activeVaultFiles.isNotEmpty) {
        for (final entry in activeVaultFiles.entries) {
          await File("${workingDir.path}/${entry.key}").writeAsString(entry.value);
        }
      } else {
        for (var entry in files.entries) {
          final filename = entry.key;
          if (filename == 'fy_vault.json') continue;
          final fileContent = entry.value;
          if (fileContent == null) continue;
          final file = File("${workingDir.path}/$filename");
          if (fileContent is String) {
            await file.writeAsString(fileContent);
          } else {
            await file.writeAsString(jsonEncode(fileContent));
          }
        }
      }

      // Restore tombstone registry with original deletion timestamps (never DateTime.now())
      if (files.containsKey('tombstone_registry.json') && files['tombstone_registry.json'] != null) {
        try {
          final rawReg = files['tombstone_registry.json'] is String
              ? jsonDecode(files['tombstone_registry.json'])
              : files['tombstone_registry.json'];
          if (rawReg is Map) {
            final Map<String, int> regMap = {};
            rawReg.forEach((k, v) {
              final cleanK = k.toString().trim();
              final ts = int.tryParse(v.toString()) ?? 0;
              if (cleanK.isNotEmpty && ts > 0) {
                regMap[cleanK] = ts;
                regMap[cleanK.toUpperCase()] = ts;
              }
            });
            await TombstoneEngine.saveTombstoneRegistry(restoredProfile.id, regMap);
          }
        } catch (_) {}
      }

      await loadAllData();
      await SnapshotWatcher.takeSnapshot(this);
      notifyListeners();

      return {
        "success": true,
        "message": "Cloud Store '" + compName + "' connected & restored successfully!",
        "companyName": compName,
      };
    } catch (e) {
      debugPrint("restoreCompanyFromCloud Error: $e");
      return {
        "success": false,
        "message": "Restore Error: $e",
      };
    }
  }
  
  Future<bool> startNewFinancialYear(String n, {bool filterZeroStock = false, bool filterExpired = false}) async { 
    await save(); 
    
    // --- 🛡️ PATH COLLISION FIX (NEW) ---
    // Gateway screen par currentFY khali ("") hoti hai, jisse path mismatch ho jata hai.
    // Isliye hum strictly pichle saal ka active folder (fYears.last) use karenge.
    String actualSourceYear = currentFY.isNotEmpty ? currentFY : activeCompany!.fYears.last;

    bool ok = await FYTransferEngine.transferData(
      companyID: activeCompany!.id, 
      businessType: activeCompany!.businessType, 
      sourceFY: actualSourceYear, // Smart Sync Source Year
      targetFY: n,
      filterZeroStock: filterZeroStock, 
      filterExpired: filterExpired,     
    ); 

    if(ok) {
      int idx = companiesRegistry.indexWhere((c) => c.id == activeCompany!.id);
      if (idx != -1) {
        List<String> updatedYears = AppDateLogic.sortFYList([...companiesRegistry[idx].fYears, n]);
        if (true) {
          companiesRegistry[idx] = CompanyProfile(
            id: activeCompany!.id,
            name: activeCompany!.name,
            businessType: activeCompany!.businessType,
            createdAt: activeCompany!.createdAt,
            password: activeCompany!.password,
            adminUser: activeCompany!.adminUser,
            address: activeCompany!.address,
            state: activeCompany!.state,
            gstin: activeCompany!.gstin,
            dlNo: activeCompany!.dlNo,
            phone: activeCompany!.phone,
            email: activeCompany!.email,
            isBiometricEnabled: activeCompany!.isBiometricEnabled,
            recoveryKey: activeCompany!.recoveryKey,
            autoLockMinutes: activeCompany!.autoLockMinutes,
            fYears: updatedYears,
          );
          activeCompany = companiesRegistry[idx];
          await saveRegistry();
        }
      }
      currentFY = n; 
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_fy_${activeCompany!.id}', n);
      D1SalesLedgerService.activeFinancialYear = n;
      await loadAllData();
      AppRealtimeCoordinator.instance.notifyAppMutation(this, action: 'NEW_FY_CREATED', entityId: n);
    } 
    return ok; 
  }

  Future<void> masterReset() async { final p = await getWorkingPath(); if(p.isNotEmpty) { final d = Directory(p); if(d.existsSync()) d.deleteSync(recursive: true); } await loadAllData(); }
  
  // --- INTEGRITY CHECKERS ---
  
  bool isPartyInUse(String partyId, String partyName) {
    bool inSales = sales.any((s) => s.partyId == partyId || s.partyName == partyName);
    bool inPurchases = purchases.any((p) => p.partyId == partyId || p.distributorName == partyName);
    bool inVouchers = vouchers.any((v) => v.partyId == partyId || v.partyName == partyName);
    bool inChallans = saleChallans.any((c) => c.partyId == partyId) || purchaseChallans.any((c) => c.partyId == partyId);
    
    return inSales || inPurchases || inVouchers || inChallans;
  }

  ProductDeleteCheckResult canDeleteMedicine(Medicine med) {
    return ProductIntegrityService.checkProductDeletionEligibility(
      med: med,
      sales: sales,
      purchases: purchases,
      saleChallans: saleChallans,
      purchaseChallans: purchaseChallans,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
      batchHistory: batchHistory,
    );
  }

  bool isProductInUse(String medId) {
    Medicine? target;
    try {
      target = medicines.firstWhere((m) => m.id == medId || (m.systemId.isNotEmpty && m.systemId == medId));
    } catch (_) {}
    if (target == null) return false;
    final res = canDeleteMedicine(target);
    return !res.canDelete;
  }


  // ===========================================================================
  // 10. GETTERS & RECOVERY
  // ===========================================================================

  NumberingSeries getDefaultSeries(String t) {
    final searchType = t.toUpperCase();
    try {
      return numberingSeries.firstWhere((s) => s.type == searchType && s.isDefault && s.isActive);
    } catch (e) {
      try {
        return numberingSeries.firstWhere((s) => s.type == searchType && s.isActive);
      } catch (e) {
        String prefix;
        if (searchType == "RECEIPT") {
          prefix = "RCT-";
        } else if (searchType == "PAYMENT") {
          prefix = "PAY-";
        } else if (searchType == "CHALLAN" || searchType == "SALE_CHALLAN") {
          prefix = "SCH-";
        } else if (searchType == "PURCHASE_CHALLAN" || searchType == "CHALLAN_PUR") {
          prefix = "PCH-";
        } else if (searchType == "PURCHASE") {
          prefix = "PUR-";
        } else if (searchType == "SALE") {
          prefix = "SALE-";
        } else if (searchType == "RETURN" || searchType == "SALE_RETURN") {
          prefix = "SR-";
        } else if (searchType == "PURCHASE_RETURN") {
          prefix = "PR-";
        } else {
          prefix = "TXN-";
        }
        return NumberingSeries(id: 'sys_$searchType', name: 'System Default', type: searchType, prefix: prefix, isDefault: true);
      }
    }
  }

  List<NumberingSeries> getSeriesByType(String t) => numberingSeries.where((s) => s.type == t).toList();

  List<String> getSortedStates() {
    final all = ["Andhra Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya", "Mizoram", "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura", "Uttar Pradesh", "Uttarakhand", "West Bengal", "Delhi", "Jammu and Kashmir", "Ladakh", "Puducherry", "Chandigarh"];
    Map<String, int> counts = {};
    for (var p in parties) {
      counts[p.state] = (counts[p.state] ?? 0) + 1;
    }
    List<String> sorted = List.from(all);
    sorted.sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
    return sorted;
  }

  // ===========================================================================
  // 📊 ADVANCED STATEMENT ENGINE (FOR PARTY LEDGER & AUDIT)
  // ===========================================================================

  
  // ===========================================================================
  // 🏛️ ENTERPRISE DOUBLE-ENTRY ACCOUNTS & DUAL-LEG ENGINE (#PH-REV-744)
  // ===========================================================================
  double calculatePartyBalance(Party p) {
    return AppAccountsCalculator.calculatePartyBalance(
      party: p,
      sales: sales,
      purchases: purchases,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
      vouchers: vouchers,
    );
  }

  double calculateCashInHandBalance() {
    return AppAccountsCalculator.calculateCashInHandBalance(
      sales: sales,
      purchases: purchases,
      vouchers: vouchers,
      openingCash: 0.0,
    );
  }

  List<Map<String, dynamic>> getCashBookStatement(DateTime from, DateTime to) {
    return AppAccountsCalculator.getCashBookStatement(
      fromDate: from,
      toDate: to,
      sales: sales,
      purchases: purchases,
      vouchers: vouchers,
      openingCash: 0.0,
    );
  }

  List<Map<String, dynamic>> getPartyStatementData({
    required String partyId,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    try {
      final p = parties.firstWhere(
        (element) => element.id == partyId || element.name.trim().toUpperCase() == partyId.trim().toUpperCase(),
      );
      return AppAccountsCalculator.getPartyStatementData(
        party: p,
        fromDate: fromDate,
        toDate: toDate,
        sales: sales,
        purchases: purchases,
        saleReturns: saleReturns,
        purchaseReturns: purchaseReturns,
        vouchers: vouchers,
      );
    } catch (_) {
      return [];
    }
  }
  // --- 🛡️ SILENT MAINTENANCE LOADERS (NEW) ---
  // Yeh system ko bina notify kiye (bina screen flash kiye) memory reload karne ki permission dete hain.
  Future<void> loadDataForMaintenanceSilently(String year) async {
    currentFY = year; 
    final dir = await getWorkingPath(); 
    if (dir.isEmpty) return;
    dynamic load(String n) { final f = File('$dir/$n'); return f.existsSync() ? jsonDecode(f.readAsStringSync()) : null; }
    
    medicines = (load('meds.json') as List?)?.map((e) => Medicine.fromMap(e)).toList() ?? DemoData.getMedicines();
    parties = (load('parts.json') as List?)?.map((e) => Party.fromMap(e)).toList() ?? [Party(id:'cash',name:"CASH",group:"Cash in Hand")];
    companies = (load('comps.json') as List?)?.map((e) => Company.fromMap(e)).toList() ?? MasterDataLibrary.getTopCompanies();
    salts = (load('salts.json') as List?)?.map((e) => Salt.fromMap(e)).toList() ?? MasterDataLibrary.getTopSalts();
    drugTypes = (load('dtypes.json') as List?)?.map((e) => DrugType.fromMap(e)).toList() ?? MasterDataLibrary.getDrugTypes();
    sales = (load('sales.json') as List?)?.map((e) => Sale.fromMap(e)).where((s) => !D1SalesLedgerService.isBillDeleted(s.id, s.billNo)).toList() ?? [];
    purchases = (load('purc.json') as List?)
        ?.map((e) => Purchase.fromMap(e))
        .where((p) => !D1SalesLedgerService.isPurchaseDeleted(p.id, p.partyId, p.billNo, p.internalNo))
        .toList() ?? [];
    vouchers = (load('vouc.json') as List?)?.map((e) => Voucher.fromMap(e)).where((v) => v.isDeleted != 1 && !D1SalesLedgerService.isBillDeleted(v.id, v.voucherNo)).toList() ?? [];
    saleChallans = (load('s_challan.json') as List?)
        ?.map((e) => SaleChallan.fromMap(e))
        .where((c) => !D1SalesLedgerService.isBillDeleted(c.id, c.billNo))
        .toList() ?? [];
    purchaseChallans = (load('p_challan.json') as List?)
        ?.map((e) => PurchaseChallan.fromMap(e))
        .where((c) => !D1SalesLedgerService.isPurchaseDeleted(c.id, c.partyId, c.billNo, c.internalNo))
        .toList() ?? [];
    saleReturns = (load('s_return.json') as List?)
        ?.map((e) => SaleReturn.fromMap(e))
        .where((r) => !D1SalesLedgerService.isBillDeleted(r.id, r.billNo))
        .toList() ?? [];
    purchaseReturns = (load('p_return.json') as List?)
        ?.map((e) => PurchaseReturn.fromMap(e))
        .where((r) => !D1SalesLedgerService.isBillDeleted(r.id, r.billNo))
        .toList() ?? [];
    cheques = (load('cheques.json') as List?)?.map((e) => ChequeEntry.fromMap(e)).toList() ?? [];
    shortages = (load('shortage.json') as List?)?.map((e) => ShortageItem.fromMap(e)).toList() ?? [];
    logs = (load('logs.json') as List?)?.map((e) => LogEntry.fromMap(e)).toList() ?? [];
    routes = (load('routs.json') as List?)?.map((e) => RouteArea.fromMap(e)).toList() ?? [];
    banks = (load('banks.json') as List?)?.map((e) => Bank.fromMap(e)).toList() ?? [];
    
    var sD = load('series.json'); if (sD!=null) numberingSeries = (sD as List).map((e)=>NumberingSeries.fromMap(e)).toList();
    var uD = load('sys_users.json'); if (uD!=null) systemUsers = (uD as List).map((e)=>SystemUser.fromMap(e)).toList();
    var bD = load('bats.json'); if (bD!=null) { batchHistory.clear(); (bD as Map).forEach((k,v)=>batchHistory[k]=(v as List).map((b)=>BatchInfo.fromMap(b)).toList()); }
  }

  void resetYearSilently() {
    currentFY = ""; // Clear silently without notifyListeners
  }

// ===========================================================================
  // 🏛️ NAYA: CASCADE PROVISIONAL BALANCE SYNC (CASCADE LOOP - NO NESTING)
  // ===========================================================================
  Future<bool> syncOpeningBalancesFromPreviousYear({
    required String startYear,
    required Function(double progress, String status) onStepProgress,
    bool reloadActiveYearAtEnd = true,
  }) async {
    if (activeCompany == null) return false;

    try {
      final root = await getApplicationDocumentsDirectory();
      final List<String> years = AppDateLogic.sortFYList(activeCompany!.fYears);
      int startIndex = years.indexOf(startYear);
      if (startIndex == -1) startIndex = 0;

      if (years.length < 2 || startIndex >= years.length - 1) {
        return true;
      }

      final int totalSteps = (years.length - 1) - startIndex;
      int completedSteps = 0;

      for (int i = startIndex; i < years.length - 1; i++) {
        final String prevFY = years[i];
        final String targetFY = years[i + 1];
        completedSteps++;

        final double stepProgress = completedSteps / totalSteps;
        onStepProgress(stepProgress, "Cascading Balances & Stock: $prevFY → $targetFY");

        final String prevPath = '${root.path}/Pharoah_Data/${activeCompany!.id}/${activeCompany!.businessType}/$prevFY';
        final String targetPath = '${root.path}/Pharoah_Data/${activeCompany!.id}/${activeCompany!.businessType}/$targetFY';

        final Directory prevDir = Directory(prevPath);
        final Directory targetDir = Directory(targetPath);

        if (!await prevDir.exists() || !await targetDir.exists()) {
          debugPrint("Sync Notice: directories missing on step $prevFY -> $targetFY");
          continue;
        }

        final Map<String, String> prevFiles = {};
        final Map<String, String> targetFiles = {};

        for (final fName in FYTransferEngine.allFyFileNames) {
          final fp = File('$prevPath/$fName');
          if (fp.existsSync()) prevFiles[fName] = await fp.readAsString();
          final ft = File('$targetPath/$fName');
          if (ft.existsSync()) targetFiles[fName] = await ft.readAsString();
        }

        final cascaded = FYTransferEngine.cascadeSingleYearStep(
          prevFiles: prevFiles,
          targetFiles: targetFiles,
          prevFY: prevFY,
          targetFY: targetFY,
        );

        for (final entry in cascaded.healedPrevFiles.entries) {
          await File('$prevPath/${entry.key}').writeAsString(entry.value);
        }
        for (final entry in cascaded.healedTargetFiles.entries) {
          await File('$targetPath/${entry.key}').writeAsString(entry.value);
        }

        addLog("SYSTEM", "Marg-Grade Multi-Year Cascade: synced opening balances & rebuilt live stock from $prevFY to $targetFY.");
        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (reloadActiveYearAtEnd && currentFY.isNotEmpty) {
        await loadAllData();
      }
      return true;
    } catch (e) {
      debugPrint("Provisional Cascade Sync Failed: $e");
      return false;
    }
  }

  // ===========================================================================
  // ✍️ SIGNATURES & CHALLAN SECURITY (RESTORED & RESOLVED)
  // ===========================================================================
  
  Future<void> addSignatureToChallan({
    required String challanId, 
    required String imagePath, 
    required String code, 
    required double amount, 
    required double qty, 
    required double x, 
    required double y
  }) async { 
    int idx = saleChallans.indexWhere((c) => c.id == challanId); 
    if (idx != -1) { 
      final s = ChallanSignature(
        id: DateTime.now().toString(), 
        imagePath: imagePath, 
        verificationCode: code, 
        signedAmount: amount, 
        signedQty: qty, 
        signDate: DateTime.now(), 
        signX: x, 
        signY: y
      ); 
      List<ChallanSignature> h = List.from(saleChallans[idx].sigHistory); 
      h.add(s); 
      saleChallans[idx].sigHistory = h; 
      saleChallans[idx].isSigned = true; 
      await save(); 
    } 
  }

  Future<String> saveSignatureFile(String cNo, Uint8List b) async { 
    final r = await getApplicationDocumentsDirectory(); 
    final d = Directory('${r.path}/Pharoah_Data/${activeCompany!.id}/Signatures'); 
    if (!await d.exists()) await d.create(recursive: true); 
    final f = File('${d.path}/Sign_${cNo}_${DateTime.now().millisecondsSinceEpoch}.png'); 
    await f.writeAsBytes(b); 
    return f.path; 
  }

  // ===========================================================================
  // 📜 MEDICINE HISTORY ENGINE (RESTORED & RESOLVED)
  // ===========================================================================

  List<Map<String, dynamic>> getMedicineHistory({
    required String partyId, 
    required String medicineId, 
    required bool isSale
  }) {
    List<Map<String, dynamic>> history = [];
    if (isSale) {
      for (var s in sales.where((s) => s.partyId == partyId && s.status == "Active")) {
        for (var it in s.items.where((it) => it.medicineID == medicineId)) {
          history.add({
            'date': s.date, 
            'billNo': s.billNo, 
            'batch': it.batch, 
            'qty': it.qty, 
            'free': it.freeQty, 
            'rate': it.rate, 
            'mrp': it.mrp, 
            'gst': it.gstRate
          });
        }
      }
    } else {
      for (var p in purchases.where((p) => p.partyId == partyId)) {
        for (var it in p.items.where((it) => it.medicineID == medicineId)) {
          history.add({
            'date': p.date, 
            'billNo': p.billNo, 
            'batch': it.batch, 
            'qty': it.qty, 
            'free': it.freeQty, 
            'rate': it.purchaseRate, 
            'mrp': it.mrp, 
            'gst': it.gstRate
          });
        }
      }
    }
    history.sort((a, b) => b['date'].compareTo(a['date']));
    return history;
  }
} // <--- THE DEFINITIVE CLOSING BRACE FOR PHAROAHMANAGER CLASS
