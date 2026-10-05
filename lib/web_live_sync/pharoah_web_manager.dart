// FILE: lib/web_live_sync/pharoah_web_manager.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'web_models.dart';
import 'web_inventory_logic_center.dart';
import 'web_sync_engine.dart';
import 'web_pharoah_numbering_engine.dart';
import 'web_app_date_logic.dart';
import 'web_cloud_config.dart';
import 'pharoah_auto_sync_service.dart';

class PharoahWebManager with ChangeNotifier {
  bool isLoading = false;
  bool isAutoLoggingIn = true;
  bool isAuthenticated = false;
  bool isCloudPushInProgress = false;
  String errorMessage = "";
  String successMessage = "";

  // Session & Store Metadata
  String activeStoreToken = "";
  String activeUsername = "";
  String activePassword = "";
  String companyName = "PHAROAH STORE";
  String financialYear = "2026-27";
  Map<String, dynamic> companyProfile = {};
  AppConfig appConfig = AppConfig();

  // 🛡️ TOMBSTONE DELETION REGISTRY
  Set<String> deletedRecordIds = {};

  // Auto-Sync Background Watchdog
  late final PharoahAutoSyncService _autoSyncService;

  // Strongly-Typed Business Models
  List<Medicine> medicines = [];
  List<Party> parties = [];
  List<Sale> sales = [];
  List<Purchase> purchases = [];
  List<Voucher> vouchers = [];
  List<SaleChallan> saleChallans = [];
  List<PurchaseChallan> purchaseChallans = [];
  List<SaleReturn> saleReturns = [];
  List<PurchaseReturn> purchaseReturns = [];
  List<ShortageItem> shortages = [];
  List<Company> companies = [];
  List<Salt> salts = [];
  List<RouteArea> routes = [];
  List<Bank> banks = [];
  List<NumberingSeries> numberingSeries = [];
  Map<String, List<BatchInfo>> batchHistory = {};

  PharoahWebManager() {
    _autoSyncService = PharoahAutoSyncService(webManager: this);
    _loadLocalTombstones();
    tryAutoLogin();
  }

  Future<void> _loadLocalTombstones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('web_tombstone_ids') ?? [];
      deletedRecordIds = list.toSet();
    } catch (_) {}
  }

  Future<void> _saveLocalTombstones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('web_tombstone_ids', deletedRecordIds.toList());
    } catch (_) {}
  }

  Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool wasLoggedIn = prefs.getBool('web_auth_logged_in') ?? false;
      String? savedToken = prefs.getString('web_auth_store_token');
      String? savedUser = prefs.getString('web_auth_username');
      String? savedPass = prefs.getString('web_auth_password');

      if (wasLoggedIn && savedToken != null && savedUser != null && savedPass != null) {
        isLoading = true;
        notifyListeners();

        final result = await WebSyncEngine.fetchStoreData(
          storeToken: savedToken,
          username: savedUser,
          password: savedPass,
        );

        if (result['success'] == true) {
          _populateDataFromCloud(savedToken, savedUser, savedPass, result);
          isAuthenticated = true;
          isLoading = false;
          isAutoLoggingIn = false;
          _autoSyncService.startRealtimeSync();
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      debugPrint("Auto-login Error: $e");
    }
    isAutoLoggingIn = false;
    isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> loginWithStoreKey({
    required String storeToken,
    required String username,
    required String password,
  }) async {
    isLoading = true;
    errorMessage = "";
    successMessage = "";
    notifyListeners();

    final result = await WebSyncEngine.fetchStoreData(
      storeToken: storeToken,
      username: username,
      password: password,
    );

    if (result['success'] == true) {
      _populateDataFromCloud(storeToken, username, password, result);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('web_auth_logged_in', true);
      await prefs.setString('web_auth_store_token', activeStoreToken);
      await prefs.setString('web_auth_username', activeUsername);
      await prefs.setString('web_auth_password', activePassword);

      isAuthenticated = true;
      isLoading = false;
      successMessage = "Store connected successfully!";
      _autoSyncService.startRealtimeSync();
      notifyListeners();
      return true;
    } else {
      isLoading = false;
      isAuthenticated = false;
      errorMessage = result['message'] ?? 'Authentication failed.';
      notifyListeners();
      return false;
    }
  }

  void _populateDataFromCloud(String token, String user, String pass, Map<String, dynamic> result) {
    activeStoreToken = token.trim().toUpperCase();
    activeUsername = user.trim();
    activePassword = pass.trim();
    companyName = result['companyName'] ?? 'STORE WORKSTATION';
    financialYear = result['fy'] ?? WebAppDateLogic.getCurrentFYString();
    companyProfile = result['profile'] ?? {};

    final Map<String, dynamic> files = result['files'] ?? {};
    _parseDownloadedFiles(files);

    rebuildInventory();
  }

  void _parseDownloadedFiles(Map<String, dynamic> files) {
    dynamic decodeJson(String fileName) {
      if (files.containsKey(fileName) && files[fileName] != null) {
        try {
          return jsonDecode(files[fileName]);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    var tData = decodeJson('tombstones.json');
    if (tData != null && tData is List) {
      deletedRecordIds.addAll(tData.map((e) => e.toString()));
      _saveLocalTombstones();
    }

    var rawMeds = (decodeJson('meds.json') as List?)
        ?.map((e) => Medicine.fromMap(e))
        .where((m) => !deletedRecordIds.contains(m.id))
        .toList() ?? [];

    Map<String, Medicine> uniqueMeds = {};
    for (var m in rawMeds) {
      String cleanKey = m.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
      if (!uniqueMeds.containsKey(cleanKey)) {
        uniqueMeds[cleanKey] = m;
      }
    }
    medicines = uniqueMeds.values.toList();

    var rawParts = (decodeJson('parts.json') as List?)
        ?.map((e) => Party.fromMap(e))
        .where((p) => !deletedRecordIds.contains(p.id))
        .toList() ?? [Party(id: 'cash', name: "CASH", group: "Cash in Hand")];

    Map<String, Party> uniqueParties = {};
    for (var p in rawParts) {
      String cleanKey = (p.gst.isNotEmpty && p.gst != 'N/A')
          ? p.gst.toUpperCase().trim()
          : p.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
      if (!uniqueParties.containsKey(cleanKey)) {
        uniqueParties[cleanKey] = p;
      }
    }
    parties = uniqueParties.values.toList();

    sales = (decodeJson('sales.json') as List?)
        ?.map((e) => Sale.fromMap(e))
        .where((s) => !deletedRecordIds.contains(s.id))
        .toList() ?? [];

    purchases = (decodeJson('purc.json') as List?)
        ?.map((e) => Purchase.fromMap(e))
        .where((p) => !deletedRecordIds.contains(p.id))
        .toList() ?? [];

    vouchers = (decodeJson('vouc.json') as List?)
        ?.map((e) => Voucher.fromMap(e))
        .where((v) => !deletedRecordIds.contains(v.id))
        .toList() ?? [];

    saleChallans = (decodeJson('s_challan.json') as List?)
        ?.map((e) => SaleChallan.fromMap(e))
        .where((c) => !deletedRecordIds.contains(c.id))
        .toList() ?? [];

    purchaseChallans = (decodeJson('p_challan.json') as List?)
        ?.map((e) => PurchaseChallan.fromMap(e))
        .where((c) => !deletedRecordIds.contains(c.id))
        .toList() ?? [];

    saleReturns = (decodeJson('s_return.json') as List?)
        ?.map((e) => SaleReturn.fromMap(e))
        .where((r) => !deletedRecordIds.contains(r.id))
        .toList() ?? [];

    purchaseReturns = (decodeJson('p_return.json') as List?)
        ?.map((e) => PurchaseReturn.fromMap(e))
        .where((r) => !deletedRecordIds.contains(r.id))
        .toList() ?? [];

    companies = (decodeJson('comps.json') as List?)?.map((e) => Company.fromMap(e)).toList() ?? [];
    salts = (decodeJson('salts.json') as List?)?.map((e) => Salt.fromMap(e)).toList() ?? [];
    routes = (decodeJson('routs.json') as List?)?.map((e) => RouteArea.fromMap(e)).toList() ?? [];
    banks = (decodeJson('banks.json') as List?)?.map((e) => Bank.fromMap(e)).toList() ?? [];
    numberingSeries = (decodeJson('series.json') as List?)?.map((e) => NumberingSeries.fromMap(e)).toList() ?? [];

    var cData = decodeJson('config.json');
    if (cData != null && cData is Map<String, dynamic>) {
      appConfig = AppConfig.fromMap(cData);
    }

    var bData = decodeJson('bats.json');
    batchHistory.clear();
    if (bData != null && bData is Map) {
      bData.forEach((k, v) {
        if (v is List) {
          batchHistory[k.toString()] = v.map((b) => BatchInfo.fromMap(b as Map<String, dynamic>)).toList();
        }
      });
    }
  }

  void rebuildInventory() {
    WebInventoryLogicCenter.rebuildWebInventory(
      medicines: medicines,
      batchHistory: batchHistory,
      purchases: purchases,
      sales: sales,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
    );
  }

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
    if (!batchHistory.containsKey(productKey)) {
      batchHistory[productKey] = [];
    }

    List<BatchInfo> history = batchHistory[productKey]!;
    int existingIdx = history.indexWhere((b) => b.batch.trim() == batchNo.trim());

    double finalRateA = rateA == 0.0 ? mrp : rateA;
    double finalRateB = rateB == 0.0 ? (rateA == 0.0 ? mrp * 0.95 : rateA * 0.95) : rateB;
    double finalRateC = rateC == 0.0 ? (rateA == 0.0 ? mrp * 0.92 : rateA * 0.92) : rateC;

    if (existingIdx != -1) {
      history[existingIdx].exp = exp;
      history[existingIdx].mrp = mrp;
      history[existingIdx].rate = rate;
      history[existingIdx].packing = packing;
      history[existingIdx].purRate = rate;
      history[existingIdx].rateA = finalRateA;
      history[existingIdx].rateB = finalRateB;
      history[existingIdx].rateC = finalRateC;
      history[existingIdx].rateCFormula = rateCFormula;
      history[existingIdx].appliedRateType = appliedRateType;
      history[existingIdx].status = status;
      if (qtyChange != 0.0) {
        history[existingIdx].qty += qtyChange;
      }
    } else {
      history.add(BatchInfo(
        batch: batchNo.trim(),
        exp: exp,
        packing: packing,
        mrp: mrp,
        rate: rate,
        qty: qtyChange,
        openingQty: qtyChange,
        isShell: false,
        purRate: rate,
        rateA: finalRateA,
        rateB: finalRateB,
        rateC: finalRateC,
        rateCFormula: rateCFormula,
        appliedRateType: appliedRateType,
        status: status,
      ));
    }
  }

  Future<bool> pushUpdatedDataToCloud() async {
    try {
      if (!isAuthenticated || activeStoreToken.isEmpty) return false;

      Map<String, String> filesPayload = {
        'meds.json': jsonEncode(medicines.map((e) => e.toMap()).toList()),
        'parts.json': jsonEncode(parties.map((e) => e.toMap()).toList()),
        'sales.json': jsonEncode(sales.map((e) => e.toMap()).toList()),
        'purc.json': jsonEncode(purchases.map((e) => e.toMap()).toList()),
        'vouc.json': jsonEncode(vouchers.map((e) => e.toMap()).toList()),
        's_challan.json': jsonEncode(saleChallans.map((e) => e.toMap()).toList()),
        'p_challan.json': jsonEncode(purchaseChallans.map((e) => e.toMap()).toList()),
        's_return.json': jsonEncode(saleReturns.map((e) => e.toMap()).toList()),
        'p_return.json': jsonEncode(purchaseReturns.map((e) => e.toMap()).toList()),
        'comps.json': jsonEncode(companies.map((e) => e.toMap()).toList()),
        'salts.json': jsonEncode(salts.map((e) => e.toMap()).toList()),
        'routs.json': jsonEncode(routes.map((e) => e.toMap()).toList()),
        'banks.json': jsonEncode(banks.map((e) => e.toMap()).toList()),
        'series.json': jsonEncode(numberingSeries.map((e) => e.toMap()).toList()),
        'config.json': jsonEncode(appConfig.toMap()),
        'bats.json': jsonEncode(batchHistory.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))),
        'tombstones.json': jsonEncode(deletedRecordIds.toList()),
      };

      final payload = {
        "action": WebCloudConfig.actionPushStore,
        "storeToken": activeStoreToken,
        "companyId": companyProfile['id'] ?? 'STORE',
        "companyName": companyName,
        "adminUser": activeUsername,
        "adminPassword": activePassword,
        "fy": financialYear,
        "registryProfile": companyProfile,
        "files": filesPayload,
        "syncedAt": DateTime.now().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse(WebCloudConfig.cloudRelayEndpoint),
        headers: WebCloudConfig.standardHeaders,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 25));

      return response.statusCode == 200 || response.body.contains("SUCCESS");
    } catch (e) {
      debugPrint("Web push error: $e");
      return false;
    }
  }

  Future<bool> addSaleAndSync(Sale sale) async {
    isCloudPushInProgress = true;
    try {
      sales.removeWhere((s) => s.id == sale.id);
      sales.add(sale);
      for (var item in sale.items) {
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
          rate: item.rate,
          rateA: item.appliedRateType == "A" ? item.rate : 0.0,
          rateB: item.appliedRateType == "B" ? item.rate : 0.0,
          rateC: item.appliedRateType == "C" ? item.rate : 0.0,
          rateCFormula: item.rateCFormula,
          appliedRateType: item.appliedRateType,
        );
      }
      rebuildInventory();
      notifyListeners();

      // ⚡ Atomic Direct Cloud Push (Awaited!)
      final success = await pushUpdatedDataToCloud();
      _autoSyncService.triggerAutoSync(action: 'DATA_SAVED', entityId: sale.id);
      return success;
    } finally {
      isCloudPushInProgress = false;
    }
  }

  void deleteSale(String saleId) {
    try {
      final s = sales.firstWhere(
        (x) => x.id == saleId || x.billNo == saleId,
        orElse: () => sales.firstWhere((x) => x.id == saleId),
      );

      Set<String> targetChallanKeys = {};
      for (var cid in s.linkedChallanIds) {
        if (cid.trim().isNotEmpty) targetChallanKeys.add(cid.trim().toUpperCase());
      }
      for (var it in s.items) {
        if (it.sourceChallanNo.trim().isNotEmpty) targetChallanKeys.add(it.sourceChallanNo.trim().toUpperCase());
        if (it.sourceChallanId.trim().isNotEmpty) targetChallanKeys.add(it.sourceChallanId.trim().toUpperCase());
      }

      if (targetChallanKeys.isNotEmpty) {
        for (var ch in saleChallans) {
          if (targetChallanKeys.contains(ch.id.trim().toUpperCase()) ||
              targetChallanKeys.contains(ch.billNo.trim().toUpperCase())) {
            ch.status = "Pending";
          }
        }
      }
    } catch (_) {}

    deletedRecordIds.add(saleId);
    _saveLocalTombstones();

    sales.removeWhere((s) => s.id == saleId || s.billNo == saleId);
    rebuildInventory();
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  Future<bool> addPurchaseAndSync(Purchase purchase) async {
    isCloudPushInProgress = true;
    try {
      purchases.removeWhere((p) => p.id == purchase.id);
      purchases.add(purchase);
      for (var item in purchase.items) {
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
      rebuildInventory();
      notifyListeners();

      // ⚡ Atomic Direct Cloud Push (Awaited!)
      final success = await pushUpdatedDataToCloud();
      _autoSyncService.triggerAutoSync(action: 'DATA_SAVED', entityId: purchase.id);
      return success;
    } finally {
      isCloudPushInProgress = false;
    }
  }

  void deletePurchase(String purId) {
    try {
      final p = purchases.firstWhere(
        (x) => x.id == purId || x.internalNo == purId || x.billNo == purId,
        orElse: () => purchases.firstWhere((x) => x.id == purId),
      );

      Set<String> targetChallanKeys = {};
      for (var cid in p.linkedChallanIds) {
        if (cid.trim().isNotEmpty) targetChallanKeys.add(cid.trim().toUpperCase());
      }
      for (var it in p.items) {
        if (it.sourceChallanNo.trim().isNotEmpty) targetChallanKeys.add(it.sourceChallanNo.trim().toUpperCase());
        if (it.sourceChallanId.trim().isNotEmpty) targetChallanKeys.add(it.sourceChallanId.trim().toUpperCase());
      }

      if (targetChallanKeys.isNotEmpty) {
        for (var ch in purchaseChallans) {
          if (targetChallanKeys.contains(ch.id.trim().toUpperCase()) ||
              targetChallanKeys.contains(ch.internalNo.trim().toUpperCase()) ||
              targetChallanKeys.contains(ch.billNo.trim().toUpperCase())) {
            ch.status = "Pending";
          }
        }
      }
    } catch (_) {}

    deletedRecordIds.add(purId);
    _saveLocalTombstones();

    purchases.removeWhere((p) => p.id == purId || p.internalNo == purId || p.billNo == purId);
    rebuildInventory();
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void deleteVoucher(String voucherId) {
    deletedRecordIds.add(voucherId);
    _saveLocalTombstones();

    vouchers.removeWhere((v) => v.id == voucherId);
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void deleteSaleChallan(String challanId) {
    deletedRecordIds.add(challanId);
    _saveLocalTombstones();

    saleChallans.removeWhere((c) => c.id == challanId);
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void deletePurchaseChallan(String challanId) {
    deletedRecordIds.add(challanId);
    _saveLocalTombstones();

    purchaseChallans.removeWhere((c) => c.id == challanId);
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void deleteSaleReturn(String returnId) {
    deletedRecordIds.add(returnId);
    _saveLocalTombstones();

    saleReturns.removeWhere((r) => r.id == returnId);
    rebuildInventory();
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void deletePurchaseReturn(String returnId) {
    deletedRecordIds.add(returnId);
    _saveLocalTombstones();

    purchaseReturns.removeWhere((r) => r.id == returnId);
    rebuildInventory();
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  String getOrCreateCompany(String name) {
    try {
      return companies.firstWhere((c) => c.name.toUpperCase() == name.trim().toUpperCase()).id;
    } catch (_) {
      String id = "CP-${1000 + companies.length + 1}";
      companies.add(Company(id: id, name: name.trim().toUpperCase()));
      _autoSyncService.triggerAutoSync();
      return id;
    }
  }

  String getOrCreateSalt(String name) {
    try {
      return salts.firstWhere((s) => s.name.toUpperCase() == name.trim().toUpperCase()).id;
    } catch (_) {
      String id = "SL-${1000 + salts.length + 1}";
      salts.add(Salt(id: id, name: name.trim().toUpperCase()));
      _autoSyncService.triggerAutoSync();
      return id;
    }
  }

  void updateParty(Party updatedParty) {
    int idx = parties.indexWhere((p) => p.id == updatedParty.id);
    if (idx != -1) {
      parties[idx] = updatedParty;
      notifyListeners();
      _autoSyncService.triggerAutoSync();
    }
  }

  void deleteParty(String partyId) {
    deletedRecordIds.add(partyId);
    _saveLocalTombstones();
    parties.removeWhere((p) => p.id == partyId);
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void addParty(Party newParty) {
    String cleanNewName = newParty.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    String cleanGst = newParty.gst.trim().toUpperCase();

    int existingIdx = parties.indexWhere((p) {
      if (newParty.id.isNotEmpty && p.id == newParty.id) return true;
      if (cleanGst.isNotEmpty && cleanGst != 'N/A' && p.gst.trim().toUpperCase() == cleanGst) return true;
      return p.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase() == cleanNewName;
    });

    if (existingIdx != -1) {
      // Overwrite/update existing party with original ID preserved
      newParty = Party(
        id: parties[existingIdx].id,
        name: newParty.name,
        group: newParty.group,
        phone: newParty.phone,
        email: newParty.email,
        address: newParty.address,
        city: newParty.city,
        state: newParty.state,
        route: newParty.route,
        gst: newParty.gst,
        dl: newParty.dl,
        dlExp: newParty.dlExp,
        pan: newParty.pan,
        transport: newParty.transport,
        priceLevel: newParty.priceLevel,
        defaultSeriesId: newParty.defaultSeriesId,
        hsnCode: newParty.hsnCode,
        opBal: newParty.opBal,
        creditLimit: newParty.creditLimit,
        creditDays: newParty.creditDays,
      );
      parties[existingIdx] = newParty;
    } else {
      parties.add(newParty);
    }
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void addMedicine(Medicine newMed) {
    String cleanNewName = newMed.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();

    int existingIdx = medicines.indexWhere((m) {
      if (newMed.id.isNotEmpty && m.id == newMed.id) return true;
      if (newMed.systemId.isNotEmpty && m.systemId == newMed.systemId) return true;
      return m.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase() == cleanNewName;
    });

    if (existingIdx != -1) {
      final old = medicines[existingIdx];
      newMed = Medicine(
        id: old.id,
        systemId: old.systemId.isNotEmpty ? old.systemId : newMed.systemId,
        uniqueCode: old.uniqueCode.isNotEmpty ? old.uniqueCode : newMed.uniqueCode,
        name: newMed.name,
        packing: newMed.packing,
        companyId: newMed.companyId.isNotEmpty ? newMed.companyId : old.companyId,
        saltId: newMed.saltId.isNotEmpty ? newMed.saltId : old.saltId,
        drugTypeId: newMed.drugTypeId.isNotEmpty ? newMed.drugTypeId : old.drugTypeId,
        rackNo: newMed.rackNo.isNotEmpty ? newMed.rackNo : old.rackNo,
        hsnCode: newMed.hsnCode,
        conversion: newMed.conversion,
        reorderLevel: old.reorderLevel,
        gst: newMed.gst,
        mrp: newMed.mrp,
        purRate: newMed.purRate,
        rateA: newMed.rateA,
        rateB: newMed.rateB,
        rateC: newMed.rateC,
        stock: old.stock > 0 ? old.stock : newMed.stock,
        drugForm: newMed.drugForm,
        isNarcotic: newMed.isNarcotic,
        isScheduleH1: newMed.isScheduleH1,
      );
      medicines[existingIdx] = newMed;
    } else {
      medicines.add(newMed);
    }
    if (!batchHistory.containsKey(newMed.identityKey)) {
      batchHistory[newMed.identityKey] = [];
    }
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void updateMedicine(Medicine updatedMed) {
    int idx = medicines.indexWhere((m) => m.id == updatedMed.id);
    if (idx != -1) {
      medicines[idx] = updatedMed;
      notifyListeners();
      _autoSyncService.triggerAutoSync();
    }
  }

  void deleteMedicine(String medId) {
    deletedRecordIds.add(medId);
    _saveLocalTombstones();

    medicines.removeWhere((item) => item.id == medId);
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  String getNextBillNumber(String type, String defaultPrefix, int defaultStart) {
    NumberingSeries? s;
    try {
      s = numberingSeries.firstWhere((ser) => ser.type == type && ser.isDefault && ser.isActive);
    } catch (_) {
      try {
        s = numberingSeries.firstWhere((ser) => ser.type == type && ser.isActive);
      } catch (_) {
        s = null;
      }
    }

    String prefix = s?.prefix ?? defaultPrefix;
    int start = s?.startNumber ?? defaultStart;

    List<dynamic> targetList;
    if (type == "SALE") {
      targetList = sales;
    } else if (type == "PURCHASE") {
      targetList = purchases;
    } else if (type == "CHALLAN") {
      targetList = saleChallans;
    } else if (type == "RETURN") {
      targetList = saleReturns;
    } else {
      targetList = vouchers;
    }

    return WebPharoahNumberingEngine.getNextNumber(
      prefix: prefix,
      startFrom: start,
      currentList: targetList,
    );
  }

  Future<void> refreshStoreData() async {
    if (!isAuthenticated || activeStoreToken.isEmpty || isCloudPushInProgress) return;
    isLoading = true;
    notifyListeners();

    final result = await WebSyncEngine.fetchStoreData(
      storeToken: activeStoreToken,
      username: activeUsername,
      password: activePassword,
    );

    if (result['success'] == true) {
      final Map<String, dynamic> files = result['files'] ?? {};
      _parseDownloadedFiles(files);
      rebuildInventory();
      successMessage = "Data refreshed live!";
    } else {
      errorMessage = result['message'] ?? 'Live Refresh failed.';
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('web_auth_logged_in', false);
    await prefs.remove('web_auth_password');

    _autoSyncService.dispose();
    isAuthenticated = false;
    activeStoreToken = "";
    activeUsername = "";
    activePassword = "";
    sales.clear();
    medicines.clear();
    parties.clear();
    purchases.clear();
    vouchers.clear();
    saleChallans.clear();
    purchaseChallans.clear();
    saleReturns.clear();
    purchaseReturns.clear();
    batchHistory.clear();
    deletedRecordIds.clear();
    notifyListeners();
  }

  // ===========================================================================
  // 📊 LEDGER STATEMENT & BALANCE ENGINE
  // ===========================================================================
  double calculatePartyBalance(Party p) {
    double total = p.opBal;
    for (var s in sales.where((s) => (s.partyId == p.id || s.partyName == p.name) && s.status == "Active")) {
      total += s.totalAmount;
    }
    for (var pur in purchases.where((pur) => (pur.partyId == p.id || pur.distributorName == p.name))) {
      total -= pur.totalAmount;
    }
    for (var sr in saleReturns.where((r) => r.partyName == p.name && r.status == "Active")) {
      total -= sr.totalAmount;
    }
    for (var pr in purchaseReturns.where((r) => r.distributorName == p.name && r.status == "Active")) {
      total += pr.totalAmount;
    }
    for (var v in vouchers.where((v) => (v.partyId == p.id || v.partyName == p.name) && v.status == "Active")) {
      if (v.type.toUpperCase() == "RECEIPT") total -= v.amount;
      if (v.type.toUpperCase() == "PAYMENT" || v.type.toUpperCase() == "EXPENSE") total += v.amount;
    }
    return total;
  }

  List<Map<String, dynamic>> getPartyStatementData({
    required String partyId,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    double runningBal = 0.0;
    String pName = "";
    Party? partyObj;

    try {
      partyObj = parties.firstWhere((element) => element.id == partyId || element.name == partyId);
      runningBal = partyObj.opBal;
      pName = partyObj.name;
    } catch (e) {
      return [];
    }

    List<Map<String, dynamic>> allTxns = [];

    for (var s in sales.where((s) => (s.partyId == partyId || s.partyName == pName) && s.status == "Active")) {
      allTxns.add({'date': s.date, 'ref': s.billNo, 'type': 'SALE', 'dr': s.totalAmount, 'cr': 0.0, 'particulars': 'Sale Invoice #${s.billNo}', 'obj': s});
    }
    for (var p in purchases.where((p) => (p.partyId == partyId || p.distributorName == pName))) {
      allTxns.add({'date': p.date, 'ref': p.billNo, 'type': 'PURCHASE', 'dr': 0.0, 'cr': p.totalAmount, 'particulars': 'Purchase Inward #${p.billNo}', 'obj': p});
    }
    for (var sr in saleReturns.where((r) => r.partyName == pName && r.status == "Active")) {
      allTxns.add({'date': sr.date, 'ref': sr.billNo, 'type': 'CN', 'dr': 0.0, 'cr': sr.totalAmount, 'particulars': 'Credit Note #${sr.billNo}', 'obj': sr});
    }
    for (var pr in purchaseReturns.where((r) => r.distributorName == pName && r.status == "Active")) {
      allTxns.add({'date': pr.date, 'ref': pr.billNo, 'type': 'DN', 'dr': pr.totalAmount, 'cr': 0.0, 'particulars': 'Debit Note #${pr.billNo}', 'obj': pr});
    }
    for (var v in vouchers.where((v) => (v.partyId == partyId || v.partyName == pName) && v.status == "Active")) {
      bool isPay = v.type.toUpperCase() == "PAYMENT" || v.type.toUpperCase() == "EXPENSE";
      allTxns.add({
        'date': v.date,
        'ref': v.voucherNo,
        'type': v.type.toUpperCase(),
        'dr': isPay ? v.amount : 0.0,
        'cr': isPay ? 0.0 : v.amount,
        'particulars': "${v.type.toUpperCase()} (${v.paymentMode})",
        'obj': v,
      });
    }

    allTxns.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    List<Map<String, dynamic>> filteredLedger = [];
    double periodOpBal = runningBal;

    DateTime fStart = DateTime(fromDate.year, fromDate.month, fromDate.day);
    DateTime tEnd = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    for (var txn in allTxns) {
      DateTime tDate = txn['date'] as DateTime;
      if (tDate.isBefore(fStart)) {
        periodOpBal += ((txn['dr'] as double) - (txn['cr'] as double));
      } else if (!tDate.isAfter(tEnd)) {
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
      'particulars': 'Opening Balance B/F',
    });

    for (var txn in filteredLedger) {
      currentRunning += ((txn['dr'] as double) - (txn['cr'] as double));
      txn['bal'] = currentRunning;
      finalResult.add(txn);
    }

    return finalResult;
  }


  // ===========================================================================
  // 📈 SHORTAGE LOGIC & 1.5x AUTO-SCAN
  // ===========================================================================
  double calculateAvgMonthlySale(String mid) {
    DateTime thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    double grossSaleQty = 0.0;
    double returnedQty = 0.0;

    for (var s in sales.where((s) => s.status == "Active" && s.date.isAfter(thirtyDaysAgo))) {
      for (var item in s.items.where((it) => it.medicineID == mid)) {
        grossSaleQty += (item.qty + item.freeQty);
      }
    }

    for (var r in saleReturns.where((r) => r.status == "Active" && r.date.isAfter(thirtyDaysAgo))) {
      for (var item in r.items.where((it) => it.medicineID == mid && !it.isBreakage)) {
        returnedQty += (item.qty + item.freeQty);
      }
    }

    double netMonthlySale = grossSaleQty - returnedQty;
    return netMonthlySale < 0 ? 0.0 : netMonthlySale;
  }

  void runAutoShortageScan() {
    shortages.removeWhere((s) => s.source == "Auto");
    for (var m in medicines) {
      double avg = calculateAvgMonthlySale(m.id);
      double requiredStock = avg * 1.5;
      if (m.stock < requiredStock && requiredStock > 0) {
        String cName = "N/A";
        try {
          cName = companies.firstWhere((c) => c.id == m.companyId).name;
        } catch (_) {
          cName = m.companyId.isNotEmpty ? m.companyId : "N/A";
        }

        shortages.add(ShortageItem(
          id: "auto_${m.id}",
          medicineId: m.id,
          medicineName: m.name,
          companyName: cName,
          qtyRequired: requiredStock - m.stock,
          currentStock: m.stock,
          date: DateTime.now(),
          source: "Auto",
        ));
      }
    }
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void addManualShortage({required Medicine med, required double qty, String cust = ""}) {
    String cName = "N/A";
    try {
      cName = companies.firstWhere((c) => c.id == med.companyId).name;
    } catch (_) {
      cName = med.companyId.isNotEmpty ? med.companyId : "N/A";
    }

    shortages.add(ShortageItem(
      id: "MAN-${DateTime.now().millisecondsSinceEpoch}",
      medicineId: med.id,
      medicineName: med.name,
      companyName: cName,
      qtyRequired: qty,
      currentStock: med.stock,
      date: DateTime.now(),
      customerName: cust,
      source: "Manual",
    ));
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }

  void deleteShortage(String id) {
    shortages.removeWhere((s) => s.id == id);
    notifyListeners();
    _autoSyncService.triggerAutoSync();
  }


  // ===========================================================================
  // 💰 VOUCHER & ACCOUNTS HELPER ENGINE
  // ===========================================================================
  List<Map<String, dynamic>> getPendingBills(String partyId, bool isReceipt) {
    List<Map<String, dynamic>> pending = [];
    DateTime now = DateTime.now();

    if (isReceipt) {
      for (var s in sales.where((s) => (s.partyId == partyId || s.partyName == partyId) && s.paymentMode == "CREDIT" && s.status == "Active")) {
        bool alreadySettled = vouchers.any((v) => v.linkedBillNumbers.contains(s.billNo) && v.status == "Active");
        if (!alreadySettled) {
          int days = now.difference(s.date).inDays;
          pending.add({'date': s.date, 'billNo': s.billNo, 'amount': s.totalAmount, 'dueDays': days});
        }
      }
    } else {
      for (var p in purchases.where((p) => (p.partyId == partyId || p.distributorName == partyId))) {
        bool alreadySettled = vouchers.any((v) => v.linkedBillNumbers.contains(p.billNo) && v.status == "Active");
        if (!alreadySettled) {
          int days = now.difference(p.date).inDays;
          pending.add({'date': p.date, 'billNo': p.billNo, 'amount': p.totalAmount, 'dueDays': days});
        }
      }
    }
    pending.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return pending;
  }

  bool isCashLimitExceeded(String partyId, double newAmount) {
    DateTime today = DateTime.now();
    double todayTotal = vouchers
        .where((v) => v.partyId == partyId && v.paymentMode == "Cash" && 
                v.date.day == today.day && v.date.month == today.month && v.status == "Active")
        .fold(0.0, (sum, v) => sum + v.amount);
    return (todayTotal + newAmount) > 200000;
  }


  void cancelVoucher(String id) {
    int i = vouchers.indexWhere((v) => v.id == id);
    if (i != -1) {
      vouchers[i].status = "Cancelled";
      if (!vouchers[i].narration.startsWith("[CANCELLED]")) {
        vouchers[i].narration = "[CANCELLED] ${vouchers[i].narration}";
      }
      notifyListeners();
      _autoSyncService.triggerAutoSync();
    }
  }

}
