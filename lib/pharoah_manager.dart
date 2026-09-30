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
import 'administration/system_user_model.dart';
import 'finance/bank_transaction_model.dart';
import 'demo_data.dart';
import 'inventory_logic_center.dart';
import 'fy_transfer_engine.dart';
import 'gateway/company_registry_model.dart';
import 'logic/app_settings_model.dart';
import 'logic/pharoah_numbering_engine.dart';
import 'master_data_library.dart';
import 'batch_sync_engine.dart';

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
    ModuleAction(title: "Batches", icon: Icons.layers, color: Colors.blueGrey, navModule: "GO_M_BATCH"),
    ModuleAction(title: "CA Profile", icon: Icons.assignment_ind_rounded, color: Colors.orange.shade900, navModule: "GO_CA_PROFILE"),
    ModuleAction(title: "Routes", icon: Icons.map, color: Colors.teal, navModule: "GO_M_ROUTE"),
    ModuleAction(title: "Company", icon: Icons.business, color: Colors.brown, navModule: "GO_M_COMP"),
    ModuleAction(title: "Salt Master", icon: Icons.science, color: Colors.deepOrange, navModule: "GO_M_SALT"),
  ];

  List<ModuleAction> get gstActions => [
    ModuleAction(title: "GSTR-1", icon: Icons.assignment, color: Colors.green, navModule: "GO_GST_1"),
    ModuleAction(title: "GSTR-3B", icon: Icons.summarize, color: Colors.blue, navModule: "GO_GST_3B"),
    ModuleAction(title: "Portal", icon: Icons.fact_check, color: Colors.teal, navModule: "GO_GST_RECON"),
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
    
    await File('$dir/bats.json').writeAsString(jsonEncode(batchHistory.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))));
    await File('$dir/config.json').writeAsString(jsonEncode(config.toMap()));
    notifyListeners();
  }

  Future<void> loadAllData() async {
    final dir = await getWorkingPath(); 
    if (dir.isEmpty) return;
    dynamic load(String n) { final f = File('$dir/$n'); return f.existsSync() ? jsonDecode(f.readAsStringSync()) : null; }
    
    var cData = load('config.json');
    if (cData != null) config = AppConfig.fromMap(cData);
    else config = AppConfig();
    
    medicines = (load('meds.json') as List?)?.map((e) => Medicine.fromMap(e)).toList() ?? DemoData.getMedicines();
    parties = (load('parts.json') as List?)?.map((e) => Party.fromMap(e)).toList() ?? [DemoData.getDemoParty(), Party(id:'cash',name:"CASH",group:"Cash in Hand")];
    companies = (load('comps.json') as List?)?.map((e) => Company.fromMap(e)).toList() ?? MasterDataLibrary.getTopCompanies();
    salts = (load('salts.json') as List?)?.map((e) => Salt.fromMap(e)).toList() ?? MasterDataLibrary.getTopSalts();
    drugTypes = (load('dtypes.json') as List?)?.map((e) => DrugType.fromMap(e)).toList() ?? MasterDataLibrary.getDrugTypes();
    sales = (load('sales.json') as List?)?.map((e) => Sale.fromMap(e)).toList() ?? [];
    purchases = (load('purc.json') as List?)?.map((e) => Purchase.fromMap(e)).toList() ?? [];
    vouchers = (load('vouc.json') as List?)?.map((e) => Voucher.fromMap(e)).toList() ?? [];
    saleChallans = (load('s_challan.json') as List?)?.map((e) => SaleChallan.fromMap(e)).toList() ?? [];
    purchaseChallans = (load('p_challan.json') as List?)?.map((e) => PurchaseChallan.fromMap(e)).toList() ?? [];
    saleReturns = (load('s_return.json') as List?)?.map((e) => SaleReturn.fromMap(e)).toList() ?? [];
    purchaseReturns = (load('p_return.json') as List?)?.map((e) => PurchaseReturn.fromMap(e)).toList() ?? [];
    cheques = (load('cheques.json') as List?)?.map((e) => ChequeEntry.fromMap(e)).toList() ?? [];
    shortages = (load('shortage.json') as List?)?.map((e) => ShortageItem.fromMap(e)).toList() ?? [];
    logs = (load('logs.json') as List?)?.map((e) => LogEntry.fromMap(e)).toList() ?? [];
    routes = (load('routs.json') as List?)?.map((e) => RouteArea.fromMap(e)).toList() ?? [];
    banks = (load('banks.json') as List?)?.map((e) => Bank.fromMap(e)).toList() ?? [];
    
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
    String sourceTag = ""
  }) async { 
    final p = parties.firstWhere((pt) => pt.id == party.id, orElse: () => party);
    sales.add(Sale(id: DateTime.now().toString(), billNo: billNo, partyId: p.id, date: date, partyName: p.name, partyGstin: p.gst, partyState: p.state, items: items, totalAmount: total, paymentMode: mode, linkedChallanIds: linkedIds ?? [], extraDiscount: extraDiscount, roundOff: roundOff, partyAddress: p.address, partyPhone: p.phone, partyEmail: p.email, partyDl: p.dl, partyPan: p.pan, partyCity: p.city, sourceTag: sourceTag)); 
    
    if (linkedIds != null) { 
      for (var id in linkedIds) { 
        int i = saleChallans.indexWhere((c) => c.id == id); 
        if (i != -1) saleChallans[i].status = "Billed"; 
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
  }) async { 
    purchases.add(Purchase(id: DateTime.now().toString(), internalNo: internalNo, billNo: billNo, partyId: party.id, date: date, entryDate: entryDate ?? DateTime.now(), distributorName: party.name, items: items, totalAmount: total, paymentMode: mode, linkedChallanIds: linkedChallanIds ?? [], sourceTag: sourceTag, extraDiscount: extraDiscount, roundOff: roundOff)); 
    
    if (linkedChallanIds != null) { 
      for (var id in linkedChallanIds) { 
        int i = purchaseChallans.indexWhere((c) => c.id == id); 
        if (i != -1) purchaseChallans[i].status = "Billed"; 
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
    int idx = purchases.indexWhere((p) => p.id == id); 
    if (idx == -1) return; 
    String t = purchases[idx].sourceTag; 
    purchases[idx] = Purchase(id: id, internalNo: internalNo, billNo: billNo, partyId: party.id, date: date, entryDate: entryDate ?? DateTime.now(), distributorName: party.name, items: items, totalAmount: total, paymentMode: mode, linkedChallanIds: linkedChallanIds, sourceTag: t, extraDiscount: extraDiscount, roundOff: roundOff); 
    
    // Rebuild first, then Save
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    await save();
    notifyListeners();
  }

  Future<void> finalizeBatchSales(List<Sale> batch) async { 
    sales.addAll(batch); 
    for (var s in batch) { if (s.linkedChallanIds.isNotEmpty) { for (var id in s.linkedChallanIds) { int i = saleChallans.indexWhere((c) => c.id == id); if (i != -1) saleChallans[i].status = "Billed"; } } } 
    if (batch.isNotEmpty && activeCompany != null) { String l = batch.last.billNo; String p = l.split(RegExp(r'\d')).first; await PharoahNumberingEngine.updateSeriesCounter(type: "SALE", companyID: activeCompany!.id, usedNumber: l, prefix: p); } 
    await save(); 
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    notifyListeners(); 
  }

  Future<void> finalizeBatchPurchases(List<Purchase> batch) async { 
    purchases.addAll(batch); 
    await save(); 
    InventoryLogicCenter.rebuildAllInventory(medicines: medicines, batchHistory: batchHistory, purchases: purchases, sales: sales, saleReturns: saleReturns, purchaseReturns: purchaseReturns); 
    notifyListeners(); 
  }

// --- CHALLANS & RETURNS ---
  void finalizeSaleChallan({
    required String billNo, 
    required DateTime date, 
    required Party party, 
    required List<BillItem> items, 
    required double total, 
    String remarks = "", 
    required String partyId
  }) { 
    saleChallans.add(SaleChallan(id: DateTime.now().toString(), billNo: billNo, partyId: partyId, date: date, partyName: party.name, partyGstin: party.gst, partyState: party.state, items: items, totalAmount: total, remarks: remarks)); 
    
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
    save(); 
  }

  void finalizePurchaseChallan({
    required String billNo, 
    required String internalNo, 
    required DateTime date, 
    required Party party, 
    required List<PurchaseItem> items, 
    required double total, 
    String remarks = "", 
    required String partyId
  }) { 
    purchaseChallans.add(PurchaseChallan(id: DateTime.now().toString(), internalNo: internalNo, billNo: billNo, partyId: partyId, date: date, distributorName: party.name, items: items, totalAmount: total, remarks: remarks)); 
    
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
    save(); 
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
    String type = "Mixed"
  }) async { 
    saleReturns.add(SaleReturn(id: DateTime.now().toString(), billNo: billNo, date: date, partyName: party.name, items: items, totalAmount: total, returnType: type, extraDiscount: extraDiscount, roundOff: roundOff, status: "Active")); 
    
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
    String type = "Mixed"
  }) async { 
    purchaseReturns.add(PurchaseReturn(id: DateTime.now().toString(), billNo: billNo, distributorName: party.name, date: date, items: items, totalAmount: total, status: "Active", returnType: type, extraDiscount: extraDiscount, roundOff: roundOff)); 
    
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
  void adjustBatchStock({required String medId, required String batchNo, required double adjQty, required String reason}) { if (batchHistory.containsKey(medId)) { try { var b = batchHistory[medId]!.firstWhere((x) => x.batch == batchNo); b.adjustmentQty += adjQty; b.adjReason = reason; save().then((_) => loadAllData()); } catch (e) {} } }
  void updateBatchMetadata({required String medId, required String batchNo, required String newExp, required double newMrp, required double newRate}) { if (batchHistory.containsKey(medId)) { try { var b = batchHistory[medId]!.firstWhere((x) => x.batch == batchNo); b.exp = newExp; b.mrp = newMrp; b.rate = newRate; save().then((_) => loadAllData()); } catch (e) {} } }
  
  // ===========================================================================
  // 💹 ADVANCED ACCOUNTING & VOUCHER ENGINE
  // ===========================================================================

  List<Map<String, dynamic>> getPendingBills(String partyId, bool isReceipt) {
    List<Map<String, dynamic>> pending = [];
    DateTime now = DateTime.now();

    if (isReceipt) {
      for (var s in sales.where((s) => s.partyId == partyId && s.paymentMode == "CREDIT" && s.status == "Active")) {
        bool alreadySettle = vouchers.any((v) => v.linkedBillNumbers.contains(s.billNo));
        if (!alreadySettle) {
          int days = now.difference(s.date).inDays;
          pending.add({'date': s.date, 'billNo': s.billNo, 'amount': s.totalAmount, 'dueDays': days});
        }
      }
    } else {
      for (var p in purchases.where((p) => p.partyId == partyId && p.paymentMode == "CREDIT")) {
        bool alreadySettle = vouchers.any((v) => v.linkedBillNumbers.contains(p.billNo));
        if (!alreadySettle) {
          int days = now.difference(p.date).inDays;
          pending.add({'date': p.date, 'billNo': p.billNo, 'amount': p.totalAmount, 'dueDays': days});
        }
      }
    }
    pending.sort((a, b) => a['date'].compareTo(b['date']));
    return pending;
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
    vouchers.add(v);
    if (activeCompany != null) {
      String seriesType = v.type.toUpperCase();
      String prefix = v.voucherNo.split(RegExp(r'\d')).first;
      await PharoahNumberingEngine.updateSeriesCounter(
        type: seriesType,
        companyID: activeCompany!.id,
        usedNumber: v.voucherNo,
        prefix: prefix,
      );
    }
    await save();
    notifyListeners();
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

  String getOrCreateCompany(String n) { try { return companies.firstWhere((c) => c.name.toUpperCase() == n.trim().toUpperCase()).id; } catch (e) { String id = "CP-${1000 + companies.length + 1}"; companies.add(Company(id: id, name: n.trim().toUpperCase())); save(); return id; } }
  String getOrCreateSalt(String n) { try { return salts.firstWhere((s) => s.name.toUpperCase() == n.trim().toUpperCase()).id; } catch (e) { String id = "SL-${1000 + salts.length + 1}"; salts.add(Salt(id: id, name: n.trim().toUpperCase())); save(); return id; } }

  void addMedicine(Medicine m, {bool doSave = true}) { medicines.add(m); if (!batchHistory.containsKey(m.identityKey)) batchHistory[m.identityKey] = []; if (doSave) save(); notifyListeners(); }
  void addRoute(RouteArea r) { routes.add(r); save(); }
  void addCompany(Company c) { companies.add(c); save(); }
  void addSalt(Salt s) { salts.add(s); save(); }
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

  void cancelVoucher(String id) {
    int i = vouchers.indexWhere((v) => v.id == id);
    if (i != -1) {
      _reverseVoucherImpact(vouchers[i]);
      vouchers[i].status = "Cancelled";
      vouchers[i].narration = "[CANCELLED] " + vouchers[i].narration;
      save();
      notifyListeners();
    }
  }

  void deleteVoucher(String id) {
    int i = vouchers.indexWhere((v) => v.id == id);
    if (i != -1) {
      _reverseVoucherImpact(vouchers[i]);
      vouchers.removeAt(i);
      save();
      notifyListeners();
    }
  }

  // ===========================================================================
  // ⚡ ADVANCED STOCK-SAFE MODIFICATION ENGINE
  // ===========================================================================

  Future<void> updateSaleReturn({required String id, required String billNo, required DateTime date, required Party party, required List<BillItem> items, required double total, double extraDiscount = 0.0, double roundOff = 0.0}) async {
    int i = saleReturns.indexWhere((r) => r.id == id);
    if (i != -1) {
      saleReturns[i] = SaleReturn(
        id: id, billNo: billNo, date: date, partyName: party.name, 
        items: items, totalAmount: total, extraDiscount: extraDiscount, 
        roundOff: roundOff, status: "Active"
      );
      
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
      purchaseReturns[i] = PurchaseReturn(
        id: id, billNo: billNo, distributorName: party.name, 
        date: date, items: items, totalAmount: total, 
        extraDiscount: extraDiscount, roundOff: roundOff, status: "Active"
      );

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
  void updateAppConfig(AppConfig c) { config = c; save(); notifyListeners(); }
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

  void deleteBill(String id) { try { final s = sales.firstWhere((x) => x.id == id); if (s.linkedChallanIds.isNotEmpty) { for (var cid in s.linkedChallanIds) { int i = saleChallans.indexWhere((c) => c.id == cid); if (i != -1) saleChallans[i].status = "Pending"; } } sales.removeWhere((x) => x.id == id); save().then((_) => loadAllData()); } catch (e) {} }
  void deletePurchase(String id) { purchases.removeWhere((p) => p.id == id); save().then((_) => loadAllData()); }
  void deleteSaleChallan(String id) { saleChallans.removeWhere((c) => c.id == id); save(); }
  void deletePurchaseChallan(String id) { purchaseChallans.removeWhere((c) => c.id == id); save(); }
  void deleteSaleReturn(String id) { saleReturns.removeWhere((r) => r.id == id); save().then((_) => loadAllData()); }
  void deletePurchaseReturn(String id) { purchaseReturns.removeWhere((r) => r.id == id); save().then((_) => loadAllData()); }

  void deleteParty(String id) {
    try {
      final p = parties.firstWhere((pt) => pt.id == id);
      if (!isPartyInUse(p.id, p.name)) {
        parties.removeWhere((pt) => pt.id == id);
        save();
      }
    } catch (e) {}
  }
  void deleteRoute(String id) { routes.removeWhere((r) => r.id == id); save(); }
  void deleteSystemUser(String id) { systemUsers.removeWhere((x) => x.id == id); save(); }
  void deleteShortage(String id) { shortages.removeWhere((s) => s.id == id); save(); }
  void deleteBank(String id) { banks.removeWhere((b) => b.id == id); save(); }

  void resetCounter(String t) { if (activeCompany != null) { String pfx = (t == "SALE_BILL") ? "INV-" : (t == "PUR_BILL" ? "PUR-" : "SCH-"); PharoahNumberingEngine.resetSeries(type: t.contains("SALE") ? "SALE" : "PURCHASE", companyID: activeCompany!.id, prefix: pfx); } notifyListeners(); }

  // ===========================================================================
  // 9. DATA REGISTRY & YEAR-END
  // ===========================================================================

  Future<void> setupNewCompanyEnvironment(CompanyProfile p, String f) async { activeCompany = p; currentFY = f; numberingSeries = [NumberingSeries(id: 's1', name: "Standard Retail", type: "SALE", prefix: "INV-", isDefault: true)]; medicines = DemoData.getMedicines(); companies = MasterDataLibrary.getTopCompanies(); salts = MasterDataLibrary.getTopSalts(); drugTypes = MasterDataLibrary.getDrugTypes(); parties = [DemoData.getDemoParty(), Party(id: 'cash', name: "CASH", group: "Cash in Hand")]; await save(); if (!companiesRegistry.any((c) => c.id == p.id)) { companiesRegistry.add(p); await saveRegistry(); } notifyListeners(); }
  
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
        List<String> updatedYears = List.from(companiesRegistry[idx].fYears);
        if (!updatedYears.contains(n)) {
          updatedYears.add(n);
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
      
      await loadAllData(); 
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

  bool isProductInUse(String medId) {
    bool inSales = sales.any((s) => s.items.any((it) => it.medicineID == medId));
    bool inPurchases = purchases.any((p) => p.items.any((it) => it.medicineID == medId));
    return inSales || inPurchases;
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
        String prefix = searchType == "RECEIPT" ? "RCT-" : (searchType == "PAYMENT" ? "PAY-" : "TXN-");
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

  List<Map<String, dynamic>> getPartyStatementData({
    required String partyId,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    double runningBal = 0.0;
    String pName = "";

    try {
      final p = parties.firstWhere((element) => element.id == partyId);
      runningBal = p.opBal;
      pName = p.name;
    } catch (e) { return []; }

    List<Map<String, dynamic>> allTxns = [];

    for (var s in sales.where((s) => s.partyId == partyId && s.status == "Active")) {
      allTxns.add({'date': s.date, 'ref': s.billNo, 'type': 'SALE', 'dr': s.totalAmount, 'cr': 0.0, 'obj': s});
    }
    for (var p in purchases.where((p) => p.partyId == partyId)) {
      allTxns.add({'date': p.date, 'ref': p.billNo, 'type': 'PURCHASE', 'dr': 0.0, 'cr': p.totalAmount, 'obj': p});
    }
    for (var sr in saleReturns.where((r) => r.partyName == pName && r.status == "Active")) {
      allTxns.add({'date': sr.date, 'ref': sr.billNo, 'type': 'CN', 'dr': 0.0, 'cr': sr.totalAmount, 'obj': sr});
    }
    for (var pr in purchaseReturns.where((r) => r.distributorName == pName && r.status == "Active")) {
      allTxns.add({'date': pr.date, 'ref': pr.billNo, 'type': 'DN', 'dr': pr.totalAmount, 'cr': 0.0, 'obj': pr});
    }
    for (var v in vouchers.where((v) => v.partyId == partyId && v.status == "Active")) {
      bool isPay = v.type.toUpperCase() == "PAYMENT";
      allTxns.add({
        'date': v.date, 'ref': v.voucherNo, 'type': v.type.toUpperCase(),
        'dr': isPay ? v.amount : 0.0, 
        'cr': isPay ? 0.0 : v.amount, 
        'obj': v
      });
    }

    allTxns.sort((a, b) => a['date'].compareTo(b['date']));

    List<Map<String, dynamic>> filteredLedger = [];
    double periodOpBal = runningBal;

    for (var txn in allTxns) {
      if (txn['date'].isBefore(fromDate)) {
        periodOpBal += (txn['dr'] - txn['cr']);
      } else if (txn['date'].isAfter(fromDate.subtract(const Duration(seconds: 1))) && 
                 txn['date'].isBefore(toDate.add(const Duration(days: 1)))) {
        filteredLedger.add(txn);
      }
    }

    double currentRunning = periodOpBal;
    List<Map<String, dynamic>> finalResult = [];
    
    finalResult.add({
      'date': fromDate, 
      'ref': 'B/F', 
      'type': 'OPENING', 
      'dr': 0.0,
      'cr': 0.0,
      'bal': periodOpBal, 
      'particulars': 'Opening Balance B/F'
    });

    for (var txn in filteredLedger) {
      currentRunning += (txn['dr'] - txn['cr']);
      txn['bal'] = currentRunning;
      finalResult.add(txn);
    }

    return finalResult;
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
    sales = (load('sales.json') as List?)?.map((e) => Sale.fromMap(e)).toList() ?? [];
    purchases = (load('purc.json') as List?)?.map((e) => Purchase.fromMap(e)).toList() ?? [];
    vouchers = (load('vouc.json') as List?)?.map((e) => Voucher.fromMap(e)).toList() ?? [];
    saleChallans = (load('s_challan.json') as List?)?.map((e) => SaleChallan.fromMap(e)).toList() ?? [];
    purchaseChallans = (load('p_challan.json') as List?)?.map((e) => PurchaseChallan.fromMap(e)).toList() ?? [];
    saleReturns = (load('s_return.json') as List?)?.map((e) => SaleReturn.fromMap(e)).toList() ?? [];
    purchaseReturns = (load('p_return.json') as List?)?.map((e) => PurchaseReturn.fromMap(e)).toList() ?? [];
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
    required Function(double progress, String status) onStepProgress
  }) async {
    if (activeCompany == null) return false;

    try {
      final root = await getApplicationDocumentsDirectory();
      List<String> years = activeCompany!.fYears;
      int startIndex = years.indexOf(startYear);
      
      if (startIndex == -1 || startIndex >= years.length - 1) {
        debugPrint("Sync Error: Invalid starting year or no subsequent year to sync.");
        return false;
      }

      int totalSteps = (years.length - 1) - startIndex;
      int completedSteps = 0;

      // Chronological loop through years
      for (int i = startIndex; i < years.length - 1; i++) {
        String prevFY = years[i];
        String targetFY = years[i + 1];
        completedSteps++;

        double stepProgress = (completedSteps / totalSteps);
        onStepProgress(stepProgress, "Syncing: $prevFY -> $targetFY");

        final prevPath = '${root.path}/Pharoah_Data/${activeCompany!.id}/${activeCompany!.businessType}/$prevFY';
        final targetPath = '${root.path}/Pharoah_Data/${activeCompany!.id}/${activeCompany!.businessType}/$targetFY';
        
        final prevDir = Directory(prevPath);
        final targetDir = Directory(targetPath);
        
        if (!await prevDir.exists() || !await targetDir.exists()) {
          debugPrint("Sync Error: directories missing on step $prevFY -> $targetFY");
          return false;
        }

        // 1. Read previous year databases directly from disk files
        File fMeds = File('$prevPath/meds.json');
        List<Medicine> prevMeds = fMeds.existsSync() ? (jsonDecode(fMeds.readAsStringSync()) as List).map((e) => Medicine.fromMap(e)).toList() : [];

        File fParts = File('$prevPath/parts.json');
        List<Party> prevParties = fParts.existsSync() ? (jsonDecode(fParts.readAsStringSync()) as List).map((e) => Party.fromMap(e)).toList() : [];

        File fSales = File('$prevPath/sales.json');
        List<Sale> prevSales = fSales.existsSync() ? (jsonDecode(fSales.readAsStringSync()) as List).map((e) => Sale.fromMap(e)).toList() : [];

        File fPurc = File('$prevPath/purc.json');
        List<Purchase> prevPurc = fPurc.existsSync() ? (jsonDecode(fPurc.readAsStringSync()) as List).map((e) => Purchase.fromMap(e)).toList() : [];

        File fVouc = File('$prevPath/vouc.json');
        List<Voucher> prevVouc = fVouc.existsSync() ? (jsonDecode(fVouc.readAsStringSync()) as List).map((e) => Voucher.fromMap(e)).toList() : [];

        File fBanks = File('$prevPath/banks.json');
        List<Bank> prevBanks = fBanks.existsSync() ? (jsonDecode(fBanks.readAsStringSync()) as List).map((e) => Bank.fromMap(e)).toList() : [];

        File fBats = File('$prevPath/bats.json');
        Map<String, dynamic> prevBatchesRaw = fBats.existsSync() ? jsonDecode(fBats.readAsStringSync()) : {};

        // 2. Read target year databases
        File fTargetParts = File('$targetPath/parts.json');
        List<Party> targetParties = fTargetParts.existsSync() ? (jsonDecode(fTargetParts.readAsStringSync()) as List).map((e) => Party.fromMap(e)).toList() : [];

        File fTargetBanks = File('$targetPath/banks.json');
        List<Bank> targetBanks = fTargetBanks.existsSync() ? (jsonDecode(fTargetBanks.readAsStringSync()) as List).map((e) => Bank.fromMap(e)).toList() : [];

        File fTargetMeds = File('$targetPath/meds.json');
        List<Medicine> targetMeds = fTargetMeds.existsSync() ? (jsonDecode(fTargetMeds.readAsStringSync()) as List).map((e) => Medicine.fromMap(e)).toList() : [];

        File fTargetBats = File('$targetPath/bats.json');
        Map<String, dynamic> targetBatchesRaw = fTargetBats.existsSync() ? jsonDecode(fTargetBats.readAsStringSync()) : {};

        // 3. Re-calculate Party Closing Balances
        Map<String, double> recalculatedPartyBals = {};
        for (var p in prevParties) {
          if (p.name == "CASH") continue;
          double bal = p.opBal;
          
          for (var s in prevSales.where((s) => s.partyName == p.name && s.status == "Active")) {
            bal += s.totalAmount;
          }
          for (var pr in prevPurc.where((pr) => pr.distributorName == p.name)) {
            bal -= pr.totalAmount;
          }
          for (var v in prevVouc.where((v) => v.partyName == p.name && v.status == "Active")) {
            String type = v.type.toUpperCase();
            if (type == "RECEIPT") {
              bal -= v.amount;
            } else if (type == "PAYMENT" || type == "EXPENSE") {
              bal += v.amount;
            }
          }
          recalculatedPartyBals[p.id] = bal;
        }

        // 4. Re-calculate Bank Balances
        Map<String, double> recalculatedBankBals = {};
        for (var b in prevBanks) {
          double bal = b.openingBalance;
          for (var v in prevVouc.where((v) => v.depositedIn.toUpperCase() == b.name.toUpperCase() && v.status == "Active")) {
            String type = v.type.toUpperCase();
            if (type == "RECEIPT") {
              bal += v.amount;
            } else if (type == "PAYMENT" || type == "EXPENSE") {
              bal -= v.amount;
            }
          }
          recalculatedBankBals[b.id] = bal;
        }

        // 5. Re-calculate Batch Stocks
        Map<String, List<BatchInfo>> recalculatedBatches = {};
        prevBatchesRaw.forEach((medKey, batchList) {
          List<dynamic> list = batchList as List;
          recalculatedBatches[medKey] = list.map((b) {
            BatchInfo bObj = BatchInfo.fromMap(b);
            if (bObj.qty < 0) bObj.qty = 0;
            bObj.openingQty = bObj.qty; 
            bObj.adjustmentQty = 0;     
            return bObj;
          }).toList();
        });

        // 6. DELTA MASTERS EXPORT (Masters Sync)
        Set<String> targetPartyIds = targetParties.map((p) => p.id).toSet();
        List<Party> missingParties = [];
        for (var p in prevParties) {
          if (!targetPartyIds.contains(p.id)) {
            p.opBal = recalculatedPartyBals[p.id] ?? p.opBal;
            missingParties.add(p);
          }
        }

        List<Party> updatedParties = targetParties.map((p) {
          if (recalculatedPartyBals.containsKey(p.id)) {
            p.opBal = recalculatedPartyBals[p.id]!;
          }
          return p;
        }).toList();
        updatedParties.addAll(missingParties);

        Set<String> targetMedKeys = targetMeds.map((m) => m.identityKey).toSet();
        List<Medicine> missingMeds = [];
        
        for (var m in prevMeds) {
          if (!targetMedKeys.contains(m.identityKey)) {
            double totalStock = 0.0;
            if (recalculatedBatches.containsKey(m.identityKey)) {
              for (var b in recalculatedBatches[m.identityKey]!) {
                totalStock += b.qty;
              }
            }
            m.stock = totalStock;
            missingMeds.add(m);
          }
        }

        List<Medicine> updatedMeds = targetMeds.map((m) {
          String key = m.identityKey;
          if (prevBatchesRaw.containsKey(key)) {
            double totalStock = 0.0;
            if (recalculatedBatches.containsKey(key)) {
              for (var b in recalculatedBatches[key]!) {
                totalStock += b.qty;
              }
            }
            m.stock = totalStock;
          }
          return m;
        }).toList();
        updatedMeds.addAll(missingMeds);

        // Delta for other static files
        File fPrevRouts = File('$prevPath/routs.json');
        List<RouteArea> prevRouts = fPrevRouts.existsSync() ? (jsonDecode(fPrevRouts.readAsStringSync()) as List).map((e) => RouteArea.fromMap(e)).toList() : [];
        File fTargetRouts = File('$targetPath/routs.json');
        List<RouteArea> targetRouts = fTargetRouts.existsSync() ? (jsonDecode(fTargetRouts.readAsStringSync()) as List).map((e) => RouteArea.fromMap(e)).toList() : [];
        Set<String> targetRouteIds = targetRouts.map((r) => r.id).toSet();
        targetRouts.addAll(prevRouts.where((r) => !targetRouteIds.contains(r.id)));

        File fPrevComps = File('$prevPath/comps.json');
        List<Company> prevComps = fPrevComps.existsSync() ? (jsonDecode(fPrevComps.readAsStringSync()) as List).map((e) => Company.fromMap(e)).toList() : [];
        File fTargetComps = File('$targetPath/comps.json');
        List<Company> targetComps = fTargetComps.existsSync() ? (jsonDecode(fTargetComps.readAsStringSync()) as List).map((e) => Company.fromMap(e)).toList() : [];
        Set<String> targetCompIds = targetComps.map((c) => c.id).toSet();
        targetComps.addAll(prevComps.where((c) => !targetCompIds.contains(c.id)));

        File fPrevSalts = File('$prevPath/salts.json');
        List<Salt> prevSalts = fPrevSalts.existsSync() ? (jsonDecode(fPrevSalts.readAsStringSync()) as List).map((e) => Salt.fromMap(e)).toList() : [];
        File fTargetSalts = File('$targetPath/salts.json');
        List<Salt> targetSalts = fTargetSalts.existsSync() ? (jsonDecode(fTargetSalts.readAsStringSync()) as List).map((e) => Salt.fromMap(e)).toList() : [];
        Set<String> targetSaltIds = targetSalts.map((s) => s.id).toSet();
        targetSalts.addAll(prevSalts.where((s) => !targetSaltIds.contains(s.id)));

        List<Bank> updatedBanks = targetBanks.map((b) {
          if (recalculatedBankBals.containsKey(b.id)) {
            b.openingBalance = recalculatedBankBals[b.id]!;
          }
          return b;
        }).toList();

        recalculatedBatches.forEach((medKey, list) {
          targetBatchesRaw[medKey] = list.map((e) => e.toMap()).toList();
        });

        // Save straight to disk
        await File('$targetPath/meds.json').writeAsString(jsonEncode(updatedMeds.map((e) => e.toMap()).toList()));
        await File('$targetPath/parts.json').writeAsString(jsonEncode(updatedParties.map((e) => e.toMap()).toList()));
        await File('$targetPath/banks.json').writeAsString(jsonEncode(updatedBanks.map((e) => e.toMap()).toList()));
        await File('$targetPath/bats.json').writeAsString(jsonEncode(targetBatchesRaw));
        await File('$targetPath/routs.json').writeAsString(jsonEncode(targetRouts.map((e) => e.toMap()).toList()));
        await File('$targetPath/comps.json').writeAsString(jsonEncode(targetComps.map((e) => e.toMap()).toList()));
        await File('$targetPath/salts.json').writeAsString(jsonEncode(targetSalts.map((e) => e.toMap()).toList()));

        addLog("SYSTEM", "Provisional Cascade: synced opening balances from $prevFY to $targetFY.");
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (currentFY.isNotEmpty) {
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
