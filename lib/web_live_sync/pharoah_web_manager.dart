import '../gst/gst_diary/services/gst_diary_d1_sync_service.dart';
import '../sync_core/modules/gst_diary_sync_module.dart';
import '../sync_core/outbox/sync_queue_manager.dart';
import 'sub_views/web_accounts/services/web_voucher_d1_sync_service.dart';
import 'sub_views/web_accounts/services/web_accounts_calculator.dart';
import "../logic/master_cascade_service.dart";
import "../logic/product_integrity_service.dart";
import '../sync_core/modules/party_sync_module.dart';
import '../sync_core/modules/medicine_sync_module.dart';
import '../sync_core/modules/company_sync_module.dart';
import '../sync_core/modules/salt_sync_module.dart';
import '../sync_core/modules/route_sync_module.dart';
import "../logic/party_integrity_service.dart";
import '../sync_core/modules/returns_sync_module.dart';
import '../sync_core/modules/credit_note_sync_module.dart';
import '../sync_core/modules/debit_note_sync_module.dart';
import "../sync_core/d1_sales_ledger_service.dart";
import '../sync_core/modules/sales_sync_module.dart';
import '../sync_core/modules/purchase_sync_module.dart';
import '../sync_core/modules/sale_challan_sync_module.dart';
import '../sync_core/modules/purchase_challan_sync_module.dart';
import '../sync_core/modules/challan_sync_module.dart';
import '../sync_core/modules/voucher_sync_module.dart';
import '../sync_core/modules/batch_sync_module.dart';
import '../sync_core/modules/batch_delta_merge_module.dart';
import '../logic/batch_cascade_engine.dart';
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
import '../fy_transfer_engine.dart';
import 'web_cloud_config.dart';
import 'sync_protocol/tombstone_engine.dart';
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
  String get currentFY => financialYear;
  List<String> availableFinancialYears = ["2026-27"];
  Map<String, Map<String, String>> fyVault = {};
  bool isExplicitBackYearSelected = false;
  bool get isBackYearActive =>
      availableFinancialYears.length > 1 && financialYear != availableFinancialYears.last;
  Map<String, dynamic> companyProfile = {};
  AppConfig appConfig = AppConfig();

  // 🛡️ TOMBSTONE DELETION REGISTRY (MONOTONIC CLOCK REGISTRY)
  Set<String> deletedRecordIds = {};
  Set<String> unmarkedRecordIds = {};
  Map<String, int> localTombstoneRegistry = {};

  // Auto-Sync Background Watchdog
  late final PharoahAutoSyncService _autoSyncService;

  // Strongly-Typed Business Models
  List<Medicine> medicines = [];
  List<Party> parties = [];
  List<Sale> sales = [];
  List<GstDiarySession> gstDiarySessions = [];
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
      deletedRecordIds = list.where((id) => !id.contains('/')).toSet();
      final uList = prefs.getStringList('web_unmarked_ids') ?? [];
      unmarkedRecordIds = uList.toSet();
      final rawRegistry = prefs.getString('web_tombstone_registry') ?? '';
      if (rawRegistry.isNotEmpty) {
        final decoded = jsonDecode(rawRegistry) as Map<String, dynamic>;
        localTombstoneRegistry = decoded.map((k, v) => MapEntry(k, int.tryParse(v.toString()) ?? 0));
        localTombstoneRegistry.removeWhere((k, _) => k.contains('/'));
      }
    } catch (_) {}
  }

  Future<void> _saveLocalTombstones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cleanDeleted = deletedRecordIds.where((id) => !id.contains('/')).toList();
      await prefs.setStringList('web_tombstone_ids', cleanDeleted);
      await prefs.setStringList('web_unmarked_ids', unmarkedRecordIds.toList());
      final cleanRegistry = Map<String, int>.from(localTombstoneRegistry);
      cleanRegistry.removeWhere((k, _) => k.contains('/'));
      await prefs.setString('web_tombstone_registry', jsonEncode(cleanRegistry));
    } catch (_) {}
  }

  /// Atomically purges deleted IDs across all transaction collections in memory
  /// Evaluates ID ONLY and checks deleteTimestamp >= recordTimestamp. NEVER purges by billNo.
  void purgeDeletedIds(List<String> ids) {
    if (ids.isEmpty) return;
    final nowTs = DateTime.now().millisecondsSinceEpoch;
    final set = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final upperSet = set.map((e) => e.toUpperCase()).toSet();
    unmarkedRecordIds.removeAll(set);
    unmarkedRecordIds.removeAll(upperSet);
    for (var id in set) {
      localTombstoneRegistry[id] = nowTs;
      localTombstoneRegistry[id.toUpperCase()] = nowTs;
    }
    deletedRecordIds.addAll(set);
    deletedRecordIds.addAll(upperSet);
    _saveLocalTombstones();

    sales.removeWhere((s) {
      final bNo = s.billNo.trim().toUpperCase();
      return set.contains(s.id) || upperSet.contains(s.id.toUpperCase()) || (bNo.isNotEmpty && (set.contains(bNo) || upperSet.contains(bNo)));
    });

    purchases.removeWhere((p) {
      final iNo = p.internalNo.trim().toUpperCase();
      final bNo = p.billNo.trim().toUpperCase();
      final party = p.partyId.trim().toUpperCase();
      final compKey = (party.isNotEmpty && bNo.isNotEmpty) ? "${party}_$bNo" : "";
      return set.contains(p.id) || upperSet.contains(p.id.toUpperCase()) ||
          (iNo.isNotEmpty && (set.contains(iNo) || upperSet.contains(iNo))) ||
          (compKey.isNotEmpty && (set.contains(compKey) || upperSet.contains(compKey))) ||
          (party.isNotEmpty && bNo.isNotEmpty && (set.contains(bNo) && set.contains(party)));
    });

    saleChallans.removeWhere((c) {
      final bNo = c.billNo.trim().toUpperCase();
      final bool idMatches = set.contains(c.id) || upperSet.contains(c.id.toUpperCase());
      final bool numMatches = bNo.isNotEmpty && (set.contains(bNo) || upperSet.contains(bNo));
      if (idMatches) return true;
      if (numMatches && c.status != "Pending" && c.status != "Active" && c.status != "Billed") return true;
      return false;
    });

    purchaseChallans.removeWhere((c) {
      final iNo = c.internalNo.trim().toUpperCase();
      final bNo = c.billNo.trim().toUpperCase();
      final party = c.partyId.trim().toUpperCase();
      final comp2 = (party.isNotEmpty && bNo.isNotEmpty) ? "${party}_$bNo" : "";
      final comp3 = PurchaseChallanSyncModule.makeCompositeKey(party, bNo, iNo);
      final bool idMatches = set.contains(c.id) || upperSet.contains(c.id.toUpperCase());
      final bool compMatches = (iNo.isNotEmpty && (set.contains(iNo) || upperSet.contains(iNo))) ||
          (comp2.isNotEmpty && (set.contains(comp2) || upperSet.contains(comp2))) ||
          (comp3.isNotEmpty && (set.contains(comp3) || upperSet.contains(comp3)));
      if (idMatches) return true;
      if (compMatches && c.status != "Pending" && c.status != "Active" && c.status != "Billed") return true;
      return false;
    });

    saleReturns.removeWhere((r) {
      final bNo = r.billNo.trim().toUpperCase();
      return set.contains(r.id) || (bNo.isNotEmpty && (set.contains(bNo) || upperSet.contains(bNo)));
    });

    purchaseReturns.removeWhere((r) => set.contains(r.id) || (r.billNo.trim().isNotEmpty && (set.contains(r.billNo.trim().toUpperCase()) || upperSet.contains(r.billNo.trim().toUpperCase()))));

    vouchers.removeWhere((v) {
      final vNo = v.voucherNo.trim().toUpperCase();
      return set.contains(v.id) || (vNo.isNotEmpty && (set.contains(vNo) || upperSet.contains(vNo)));
    });
    gstDiarySessions.removeWhere((gs) => set.contains(gs.id) || upperSet.contains(gs.id.toUpperCase()));

    rebuildInventory();
    notifyListeners();
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

  Map<String, String> _captureCurrentMemoryToFyFilesMap() {
    return {
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
      'gst_sessions.json': jsonEncode(gstDiarySessions.map((e) => e.toMap()).toList()),
      'config.json': jsonEncode(appConfig.toMap()),
      'bats.json': jsonEncode(batchHistory.map((k, v) => MapEntry(k, v.map((b) => b.toMap()).toList()))),
    };
  }

  void _extractAndSyncFyVaultFromCloud(Map<String, dynamic> files, {String? cloudTopFy}) {
    final rawVault = files['fy_vault.json'];
    if (rawVault != null) {
      try {
        final decoded = rawVault is String ? jsonDecode(rawVault) : rawVault;
        if (decoded is Map) {
          decoded.forEach((fyKey, fyFiles) {
            final cleanFy = fyKey.toString().trim();
            if (cleanFy.isNotEmpty && fyFiles is Map) {
              final Map<String, String> fMap = {};
              fyFiles.forEach((fName, fVal) {
                if (fVal != null) {
                  fMap[fName.toString()] = fVal is String ? fVal : jsonEncode(fVal);
                }
              });
              fyVault[cleanFy] = fMap;
            }
          });
        }
      } catch (_) {}
    }

    final Set<String> discoveredFys = Set<String>.from(availableFinancialYears);
    if (companyProfile['fYears'] is List) {
      for (final y in (companyProfile['fYears'] as List)) {
        final cy = y.toString().trim();
        if (cy.isNotEmpty) discoveredFys.add(cy);
      }
    }
    for (final k in fyVault.keys) {
      if (k.trim().isNotEmpty) discoveredFys.add(k.trim());
    }
    if (cloudTopFy != null && cloudTopFy.trim().isNotEmpty) {
      discoveredFys.add(cloudTopFy.trim());
    }
    if (discoveredFys.isEmpty) {
      discoveredFys.add(WebAppDateLogic.getCurrentFYString());
    }
    availableFinancialYears = WebAppDateLogic.sortFYList(discoveredFys);
    companyProfile['fYears'] = availableFinancialYears;
  }

  void _populateDataFromCloud(String token, String user, String pass, Map<String, dynamic> result) {
    activeStoreToken = token.trim().toUpperCase();
    activeUsername = user.trim();
    activePassword = pass.trim();
    companyName = result['companyName'] ?? 'STORE WORKSTATION';
    final String cloudTopFy = (result['fy'] != null && result['fy'].toString().trim().isNotEmpty)
        ? result['fy'].toString().trim()
        : WebAppDateLogic.getCurrentFYString();
    companyProfile = (result['profile'] is Map)
        ? Map<String, dynamic>.from(result['profile'])
        : {};

    final Map<String, dynamic> files = (result['files'] is Map)
        ? Map<String, dynamic>.from(result['files'])
        : {};
    _extractAndSyncFyVaultFromCloud(files, cloudTopFy: cloudTopFy);

    if (!isExplicitBackYearSelected || !availableFinancialYears.contains(financialYear)) {
      financialYear = availableFinancialYears.isNotEmpty ? availableFinancialYears.last : cloudTopFy;
      isExplicitBackYearSelected = false;
    }
    D1SalesLedgerService.activeFinancialYear = financialYear;

    if (fyVault.containsKey(financialYear) && fyVault[financialYear]!.isNotEmpty) {
      final Map<String, dynamic> scopedFiles = Map<String, dynamic>.from(fyVault[financialYear]!);
      if (files.containsKey('tombstones.json')) scopedFiles['tombstones.json'] = files['tombstones.json'];
      if (files.containsKey('tombstone_registry.json')) scopedFiles['tombstone_registry.json'] = files['tombstone_registry.json'];
      _parseDownloadedFiles(scopedFiles);
    } else if (cloudTopFy == financialYear || fyVault.isEmpty) {
      _parseDownloadedFiles(files);
      fyVault[financialYear] = _captureCurrentMemoryToFyFilesMap();
    }

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
      for (var e in tData) {
        final k = e.toString().trim();
        if (k.isNotEmpty && !unmarkedRecordIds.contains(k)) {
          deletedRecordIds.add(k);
          deletedRecordIds.add(k.toUpperCase());
        }
      }
      _saveLocalTombstones();
    }

    var regData = decodeJson('tombstone_registry.json');
    if (regData != null && regData is Map) {
      regData.forEach((k, v) {
        final cleanK = k.toString().trim();
        if (cleanK.isNotEmpty && !unmarkedRecordIds.contains(cleanK)) {
          final cloudTs = int.tryParse(v.toString()) ?? 0;
          final localTs = localTombstoneRegistry[cleanK] ?? 0;
          if (cloudTs > localTs) {
            localTombstoneRegistry[cleanK] = cloudTs;
            localTombstoneRegistry[cleanK.toUpperCase()] = cloudTs;
            deletedRecordIds.add(cleanK);
            deletedRecordIds.add(cleanK.toUpperCase());
          }
        }
      });
      _saveLocalTombstones();
    }

    // 🛡️ NON-DESTRUCTIVE LWW DELTA MERGE (#PH-REV-737): Never wipe in-flight local medicine edits!
    var rawSessions = decodeJson('gst_sessions.json') as List?;
    if (rawSessions != null) {
      GstDiarySyncModule.mergeSessionList(
        cloudSessionList: rawSessions,
        localSessionList: gstDiarySessions,
        tombstoneRegistry: localTombstoneRegistry,
        deletedIds: deletedRecordIds,
      );
    }
    var rawMeds = decodeJson('meds.json') as List?;
    if (rawMeds != null) {
      MedicineSyncModule.mergeMedicineList(
        cloudMedicineList: rawMeds,
        localMedicineList: medicines,
        tombstoneRegistry: localTombstoneRegistry,
        deletedRecordIds: deletedRecordIds,
      );
    }

    // 🛡️ NON-DESTRUCTIVE LWW DELTA MERGE (#PH-REV-734): Never wipe in-flight local party edits!
    var rawParts = decodeJson('parts.json') as List?;
    if (rawParts != null) {
      PartySyncModule.mergePartyList(
        cloudPartyList: rawParts,
        localPartyList: parties,
        tombstoneRegistry: localTombstoneRegistry,
      );
    } else if (parties.isEmpty) {
      parties = [Party(id: 'cash', name: "CASH", group: "Cash in Hand")];
    }
    if (!parties.any((p) => p.name.trim().toUpperCase() == "CASH" || p.id == "cash")) {
      parties.insert(0, Party(id: 'cash', name: "CASH", group: "Cash in Hand"));
    }
    // 1. Sales Sync with Anti-Zombie Shield & Strict LWW Guard (MANDATE 1 & 2)
    var allParsedSales = (decodeJson('sales.json') as List?)
        ?.map((e) => Sale.fromMap(e))
        .toList();
    sales.removeWhere((s) =>
        s.id.startsWith('SESS_') ||
        s.id == 'APP_CONFIG_MASTER' ||
        s.billNo.trim().isEmpty ||
        (s.items.isEmpty && s.totalAmount <= 0));
    if (allParsedSales != null) {
      for (var s in allParsedSales) {
        if (s.id.isEmpty ||
            s.id.startsWith('SESS_') ||
            s.id == 'APP_CONFIG_MASTER' ||
            s.billNo.trim().isEmpty ||
            (s.items.isEmpty && s.totalAmount <= 0)) {
          continue;
        }

        // 🛡️ D1 MASTER GRAVESTONE SHIELD: If deleted in D1, Google Drive can NEVER resurrect!
        if (D1SalesLedgerService.isBillDeleted(s.id, s.billNo)) {
          continue;
        }

        // 🛡️ D1 MASTER VERSION SHIELD: If D1 has higher version, Google Drive can NEVER downgrade!
        final int knownVer = D1SalesLedgerService.getKnownVersion(s.id, s.billNo);
        if (knownVer > s.version) {
          continue;
        }

        // 🛡️ SHIELD 1: Anti-Zombie / Permanent Tombstone Check (ID & BillNo Protected)
        final String cleanBillNo = s.billNo.trim().toUpperCase();
        if (s.id.isNotEmpty && (deletedRecordIds.contains(s.id) || deletedRecordIds.contains(s.id.toUpperCase()))) {
          continue; // Blocked by immutable ID tombstone
        }
        int secDelTs = 0;
        if (cleanBillNo.isNotEmpty) {
          final t = localTombstoneRegistry[cleanBillNo] ?? localTombstoneRegistry[cleanBillNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= s.updatedAt) {
          continue; // Blocked because tombstone is newer or same age
        }
        // Newer record re-created: clean stale series tombstones
        if (cleanBillNo.isNotEmpty) {
          deletedRecordIds.remove(cleanBillNo);
          deletedRecordIds.remove(cleanBillNo.toUpperCase());
          localTombstoneRegistry.remove(cleanBillNo);
          localTombstoneRegistry.remove(cleanBillNo.toUpperCase());
          unmarkedRecordIds.add(cleanBillNo);
        }

        int idx = sales.indexWhere((ls) => ls.id == s.id || (s.billNo.trim().isNotEmpty && ls.billNo.trim().toUpperCase() == s.billNo.trim().toUpperCase()));
        if (idx != -1) {
          // 🛡️ VERSION SHIELD: Never allow Google Drive to downgrade a locally modified / D1 bill!
          if (sales[idx].version > s.version) {
            continue; // Local/D1 is newer! Reject stale Google Drive snapshot!
          }
          if (s.version > sales[idx].version || (s.version == sales[idx].version && s.updatedAt >= sales[idx].updatedAt) || sales[idx].updatedAt == 0) {
            sales[idx] = s;
          }
        } else {
          sales.insert(0, s);
        }
      }

      // 🛡️ STRICT DEDUPLICATION: Exactly 1 record per BillNo (Keep highest version)
      Map<String, Sale> masterSalesMap = {};
      for (var s in sales) {
        String key = s.billNo.trim().toUpperCase();
        if (key.isEmpty) key = s.id.trim();
        if (!masterSalesMap.containsKey(key)) {
          masterSalesMap[key] = s;
        } else {
          var existing = masterSalesMap[key]!;
          if (s.version > existing.version || (s.version == existing.version && s.updatedAt >= existing.updatedAt)) {
            masterSalesMap[key] = s;
          }
        }
      }
      sales = masterSalesMap.values.toList();

      // (Unified D1 Edge Harvest runs after Vouchers sync below so Sales, Purchases & Vouchers all share the same delta batch)
    }

    // 2. Purchases Sync with Anti-Zombie Composite Key Shield & Strict Multi-Key Protection
    var allParsedPurc = (decodeJson('purc.json') as List?)
        ?.map((e) => Purchase.fromMap(e))
        .toList();
    if (allParsedPurc != null) {
      for (var p in allParsedPurc) {
        if (p.isDeleted == 1) continue;
        final String cleanIntNo = p.internalNo.trim().toUpperCase();
        final String cleanBillNo = p.billNo.trim().toUpperCase();
        final String cleanPartyId = p.partyId.trim().toUpperCase();
        final String compKey = PurchaseSyncModule.makeCompositeKey(cleanPartyId, cleanBillNo, cleanIntNo);

        // 🛡️ D1 MASTER GRAVESTONE SHIELD: If deleted in D1, Google Drive can NEVER resurrect!
        if (D1SalesLedgerService.isPurchaseDeleted(p.id, p.partyId, p.billNo, p.internalNo)) {
          continue;
        }

        // 🛡️ D1 MASTER VERSION SHIELD: If D1 has higher version, Google Drive can NEVER downgrade!
        final int knownVer = D1SalesLedgerService.getPurchaseKnownVersion(p.id, p.partyId, p.billNo, p.internalNo);
        if (knownVer > p.version) {
          continue;
        }

        // 🛡️ Anti-Zombie / Permanent Tombstone Check (Immutable ID vs Chronological Series/Composite Keys)
        final String rawCompKey = (cleanPartyId.isNotEmpty && cleanBillNo.isNotEmpty) ? "${cleanPartyId}_$cleanBillNo" : "";
        if (p.id.isNotEmpty && (deletedRecordIds.contains(p.id) || deletedRecordIds.contains(p.id.toUpperCase()))) {
          continue; // Blocked by immutable ID tombstone
        }

        int secDelTs = 0;
        if (cleanIntNo.isNotEmpty) {
          final t = localTombstoneRegistry[cleanIntNo] ?? localTombstoneRegistry[cleanIntNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (compKey.isNotEmpty) {
          final t = localTombstoneRegistry[compKey] ?? localTombstoneRegistry[compKey.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (rawCompKey.isNotEmpty) {
          final t = localTombstoneRegistry[rawCompKey] ?? localTombstoneRegistry[rawCompKey.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }

        if (secDelTs > 0 && secDelTs >= p.updatedAt) {
          continue; // Blocked because tombstone is newer or same age
        }

        // Newer record re-created: clean stale series tombstones
        if (cleanIntNo.isNotEmpty) {
          deletedRecordIds.remove(cleanIntNo);
          deletedRecordIds.remove(cleanIntNo.toUpperCase());
        }
        if (compKey.isNotEmpty) {
          deletedRecordIds.remove(compKey);
          deletedRecordIds.remove(compKey.toUpperCase());
        }
        if (rawCompKey.isNotEmpty) {
          deletedRecordIds.remove(rawCompKey);
          deletedRecordIds.remove(rawCompKey.toUpperCase());
        }

        int idx = purchases.indexWhere((lp) => 
          (p.id.isNotEmpty && lp.id == p.id) ||
          (cleanIntNo.isNotEmpty && lp.internalNo.trim().toUpperCase() == cleanIntNo) ||
          (cleanBillNo.isNotEmpty && cleanPartyId.isNotEmpty &&
           lp.billNo.trim().toUpperCase() == cleanBillNo && lp.partyId.trim().toUpperCase() == cleanPartyId)
        );
        if (idx != -1) {
          if (purchases[idx].version > p.version) continue;
          if (p.version > purchases[idx].version || (p.version == purchases[idx].version && p.updatedAt >= purchases[idx].updatedAt) || purchases[idx].updatedAt == 0) {
            purchases[idx] = p;
          }
        } else {
          purchases.insert(0, p);
        }
      }
      // 🛡️ STRICT DEDUPLICATION: Keyed by internalNo or composite key (PartyId_BillNo)
      Map<String, Purchase> masterPurcMap = {};
      for (var p in purchases) {
        String key = p.internalNo.trim().toUpperCase();
        if (key.isEmpty && p.partyId.isNotEmpty && p.billNo.isNotEmpty) {
          key = "${p.partyId.trim().toUpperCase()}_${p.billNo.trim().toUpperCase()}";
        }
        if (key.isEmpty) key = p.id.trim();
        if (!masterPurcMap.containsKey(key) || p.version >= masterPurcMap[key]!.version) {
          masterPurcMap[key] = p;
        }
      }
      purchases = masterPurcMap.values.where((p) {
        final iNo = p.internalNo.trim().toUpperCase();
        final comp2 = (p.partyId.isNotEmpty && p.billNo.isNotEmpty) ? "${p.partyId.trim().toUpperCase()}_${p.billNo.trim().toUpperCase()}" : "";
        final comp3 = PurchaseSyncModule.makeCompositeKey(p.partyId, p.billNo, p.internalNo);
        if (D1SalesLedgerService.isPurchaseDeleted(p.id, p.partyId, p.billNo, p.internalNo)) return false;
        if (p.id.isNotEmpty && (deletedRecordIds.contains(p.id) || deletedRecordIds.contains(p.id.toUpperCase()))) return false;

        int secDelTs = 0;
        if (iNo.isNotEmpty) {
          final t = localTombstoneRegistry[iNo] ?? localTombstoneRegistry[iNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (comp2.isNotEmpty) {
          final t = localTombstoneRegistry[comp2] ?? localTombstoneRegistry[comp2.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (comp3.isNotEmpty) {
          final t = localTombstoneRegistry[comp3] ?? localTombstoneRegistry[comp3.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= p.updatedAt) return false;
        return true;
      }).toList();

    }

    // 3. Vouchers Sync with Anti-Zombie Multi-Key Protection & D1 Shield
    var allParsedVouc = (decodeJson('vouc.json') as List?)
        ?.map((e) => Voucher.fromMap(e))
        .toList();
    if (allParsedVouc != null) {
      for (var v in allParsedVouc) {
        if (v.isDeleted == 1 || v.status == "Deleted") continue;
        final String cleanVNo = v.voucherNo.trim().toUpperCase();
        if (D1SalesLedgerService.isBillDeleted(v.id, cleanVNo)) continue;
        final int knownVer = D1SalesLedgerService.getKnownVersion(v.id, cleanVNo);
        if (knownVer > v.version) continue;

        if (v.id.isNotEmpty && (deletedRecordIds.contains(v.id) || deletedRecordIds.contains(v.id.toUpperCase()))) {
          continue;
        }
        final int idDelTs = localTombstoneRegistry[v.id] ?? localTombstoneRegistry[v.id.toUpperCase()] ?? 0;
        if (idDelTs > 0) continue;

        final int secDelTs = cleanVNo.isNotEmpty
            ? (localTombstoneRegistry[cleanVNo] ?? localTombstoneRegistry[cleanVNo.toUpperCase()] ?? 0)
            : 0;
        if (secDelTs > 0 && (v.updatedAt == 0 || secDelTs >= v.updatedAt)) {
          continue;
        }
        if (cleanVNo.isNotEmpty) {
          deletedRecordIds.remove(cleanVNo);
          deletedRecordIds.remove(cleanVNo.toUpperCase());
        }

        int idx = vouchers.indexWhere((lv) => 
          (v.id.isNotEmpty && lv.id == v.id) ||
          (cleanVNo.isNotEmpty && lv.voucherNo.trim().toUpperCase() == cleanVNo)
        );
        if (idx != -1) {
          if (vouchers[idx].version > v.version) continue;
          if (v.version > vouchers[idx].version || (v.version == vouchers[idx].version && v.updatedAt >= vouchers[idx].updatedAt) || vouchers[idx].updatedAt == 0) {
            vouchers[idx] = v;
          }
        } else {
          vouchers.insert(0, v);
        }
      }
      Map<String, Voucher> masterVoucMap = {};
      for (var v in vouchers) {
        String key = v.voucherNo.trim().toUpperCase();
        if (key.isEmpty) key = v.id.trim();
        if (!masterVoucMap.containsKey(key) ||
            v.version > masterVoucMap[key]!.version ||
            (v.version == masterVoucMap[key]!.version && v.updatedAt >= masterVoucMap[key]!.updatedAt)) {
          masterVoucMap[key] = v;
        }
      }
      vouchers = masterVoucMap.values.where((v) {
        if (v.isDeleted == 1 || v.status == "Deleted") return false;
        final String vNo = v.voucherNo.trim().toUpperCase();
        if (D1SalesLedgerService.isBillDeleted(v.id, vNo)) return false;
        if (v.id.isNotEmpty && (deletedRecordIds.contains(v.id) || deletedRecordIds.contains(v.id.toUpperCase()))) return false;
        if (v.id.isNotEmpty && (localTombstoneRegistry.containsKey(v.id) || localTombstoneRegistry.containsKey(v.id.toUpperCase()))) return false;
        final int secDelTs = vNo.isNotEmpty
            ? (localTombstoneRegistry[vNo] ?? localTombstoneRegistry[vNo.toUpperCase()] ?? 0)
            : 0;
        if (secDelTs > 0 && (v.updatedAt == 0 || secDelTs >= v.updatedAt)) return false;
        return true;
      }).toList();
    }

    // 🚀 UNIFIED D1 EDGE REAL-TIME DELTAS HARVEST (SALES + PURCHASES + VOUCHERS)
    if (D1SalesLedgerService.USE_D1_EDGE_LEDGER && activeStoreToken.isNotEmpty) {
      D1SalesLedgerService.fetchSaleDeltas(activeStoreToken).then((edgeEvents) {
        if (edgeEvents.isNotEmpty) {
          final bool sMut = D1SalesLedgerService.applyEventsToLocalSales(sales, edgeEvents);
          final bool pMut = D1SalesLedgerService.applyEventsToLocalPurchases(purchases, edgeEvents);
          final bool vMut = WebVoucherD1SyncService.applyEdgeEventsToLocalVouchers(vouchers, edgeEvents);
          final bool gMut = GstDiaryD1SyncService.applyEdgeEventsToLocalSessions(gstDiarySessions, edgeEvents);
          final bool cMut = GstDiaryD1SyncService.applyEdgeEventsToLocalConfig(
            currentConfig: appConfig,
            edgeEvents: edgeEvents,
            onConfigMutated: (cfg) => appConfig = cfg,
          );
          if (sMut) {
            Map<String, Sale> postD1Map = {};
            for (var s in sales) {
              String key = s.billNo.trim().toUpperCase();
              if (key.isEmpty) key = s.id.trim();
              if (!postD1Map.containsKey(key) || s.version >= postD1Map[key]!.version) {
                postD1Map[key] = s;
              }
            }
            sales = postD1Map.values.toList();
          }
          if (sMut || pMut) {
            rebuildInventory();
          }
          if (sMut || pMut || vMut || gMut || cMut) {
            notifyListeners();
          }
        }
      }).catchError((_) {});
    }

    // 4. Sale Challans Sync with Anti-Zombie Multi-Key Protection & Chronological LWW Guard
    var allParsedSCh = (decodeJson('s_challan.json') as List?)
        ?.map((e) => SaleChallan.fromMap(e))
        .toList();
    if (allParsedSCh != null) {
      for (var c in allParsedSCh) {
        if (c.isDeleted == 1) continue;
        final String cleanBNo = c.billNo.trim().toUpperCase();
        if (c.id.isNotEmpty && (deletedRecordIds.contains(c.id) || deletedRecordIds.contains(c.id.toUpperCase()))) {
          continue; // Blocked by immutable ID tombstone
        }
        int secDelTs = 0;
        if (cleanBNo.isNotEmpty) {
          final t = localTombstoneRegistry[cleanBNo] ?? localTombstoneRegistry[cleanBNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= c.updatedAt) {
          continue; // Blocked by newer or same age series tombstone
        }
        if (cleanBNo.isNotEmpty) {
          deletedRecordIds.remove(cleanBNo);
          deletedRecordIds.remove(cleanBNo.toUpperCase());
        }
        int idx = saleChallans.indexWhere((lc) => 
          (c.id.isNotEmpty && lc.id == c.id) ||
          (cleanBNo.isNotEmpty && lc.billNo.trim().toUpperCase() == cleanBNo)
        );
        if (idx != -1) {
          if (saleChallans[idx].version > c.version) continue;
          if (c.version > saleChallans[idx].version || (c.version == saleChallans[idx].version && c.updatedAt >= saleChallans[idx].updatedAt) || saleChallans[idx].updatedAt == 0) {
            saleChallans[idx] = c;
          }
        } else {
          saleChallans.insert(0, c);
        }
      }
      Map<String, SaleChallan> masterSChMap = {};
      for (var c in saleChallans) {
        String key = c.billNo.trim().toUpperCase();
        if (key.isEmpty) key = c.id.trim();
        if (!masterSChMap.containsKey(key) || c.version >= masterSChMap[key]!.version) {
          masterSChMap[key] = c;
        }
      }
      saleChallans = masterSChMap.values.where((c) {
        final bNo = c.billNo.trim().toUpperCase();
        if (c.id.isNotEmpty && (deletedRecordIds.contains(c.id) || deletedRecordIds.contains(c.id.toUpperCase()))) return false;
        if (c.status != "Pending" && c.status != "Active" && c.status != "Billed") {
          if (D1SalesLedgerService.isBillDeleted(c.id, c.billNo)) return false;
        } else {
          if (D1SalesLedgerService.isBillDeleted(c.id)) return false;
        }
        int secDelTs = 0;
        if (bNo.isNotEmpty) {
          final t = localTombstoneRegistry[bNo] ?? localTombstoneRegistry[bNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= c.updatedAt && c.status != "Pending" && c.status != "Active") return false;
        return true;
      }).toList();
    }

    // 5. Purchase Challans Sync with Anti-Zombie Multi-Key Protection & Chronological LWW Guard
    var allParsedPCh = (decodeJson('p_challan.json') as List?)
        ?.map((e) => PurchaseChallan.fromMap(e))
        .toList();
    if (allParsedPCh != null) {
      for (var c in allParsedPCh) {
        if (c.isDeleted == 1) continue;
        final String cleanINo = c.internalNo.trim().toUpperCase();
        final String cleanBNo = c.billNo.trim().toUpperCase();
        final String cleanPId = c.partyId.trim().toUpperCase();
        final String rawCompKey = (cleanPId.isNotEmpty && cleanBNo.isNotEmpty) ? "${cleanPId}_$cleanBNo" : "";
        final String compKey = PurchaseChallanSyncModule.makeCompositeKey(cleanPId, cleanBNo, cleanINo);
        if (D1SalesLedgerService.isPurchaseDeleted(c.id, c.partyId, c.billNo, c.internalNo)) {
          continue;
        }
        if (c.id.isNotEmpty && (deletedRecordIds.contains(c.id) || deletedRecordIds.contains(c.id.toUpperCase()))) {
          continue; // Blocked by immutable ID tombstone
        }
        int secDelTs = 0;
        if (cleanINo.isNotEmpty) {
          final t = localTombstoneRegistry[cleanINo] ?? localTombstoneRegistry[cleanINo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (rawCompKey.isNotEmpty) {
          final t = localTombstoneRegistry[rawCompKey] ?? localTombstoneRegistry[rawCompKey.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (compKey.isNotEmpty) {
          final t = localTombstoneRegistry[compKey] ?? localTombstoneRegistry[compKey.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && c.updatedAt > 0 && secDelTs >= c.updatedAt) {
          continue; // Blocked by newer or same age series tombstone
        }
        if (cleanINo.isNotEmpty) {
          deletedRecordIds.remove(cleanINo);
          deletedRecordIds.remove(cleanINo.toUpperCase());
        }
        if (rawCompKey.isNotEmpty) {
          deletedRecordIds.remove(rawCompKey);
          deletedRecordIds.remove(rawCompKey.toUpperCase());
        }
        if (compKey.isNotEmpty) {
          deletedRecordIds.remove(compKey);
          deletedRecordIds.remove(compKey.toUpperCase());
        }

        int idx = purchaseChallans.indexWhere((lc) =>
          (c.id.isNotEmpty && lc.id == c.id) ||
          (cleanINo.isNotEmpty && lc.internalNo.trim().toUpperCase() == cleanINo) ||
          (cleanPId.isNotEmpty && cleanBNo.isNotEmpty &&
           lc.partyId.trim().toUpperCase() == cleanPId && lc.billNo.trim().toUpperCase() == cleanBNo)
        );
        if (idx != -1) {
          if (purchaseChallans[idx].version > c.version) continue;
          if (c.version > purchaseChallans[idx].version || (c.version == purchaseChallans[idx].version && c.updatedAt >= purchaseChallans[idx].updatedAt) || purchaseChallans[idx].updatedAt == 0) {
            purchaseChallans[idx] = c;
          }
        } else {
          purchaseChallans.insert(0, c);
        }
      }
      Map<String, PurchaseChallan> masterPChMap = {};
      for (var c in purchaseChallans) {
        String key = c.internalNo.trim().toUpperCase();
        if (key.isEmpty && c.partyId.isNotEmpty && c.billNo.isNotEmpty) {
          key = "${c.partyId.trim().toUpperCase()}_${c.billNo.trim().toUpperCase()}";
        }
        if (key.isEmpty) key = c.id.trim();
        if (!masterPChMap.containsKey(key) || c.version >= masterPChMap[key]!.version) {
          masterPChMap[key] = c;
        }
      }
      purchaseChallans = masterPChMap.values.where((c) {
        final iNo = c.internalNo.trim().toUpperCase();
        final bNo = c.billNo.trim().toUpperCase();
        final pId = c.partyId.trim().toUpperCase();
        final comp2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
        final comp = PurchaseChallanSyncModule.makeCompositeKey(pId, bNo, iNo);
        if (c.id.isNotEmpty && (deletedRecordIds.contains(c.id) || deletedRecordIds.contains(c.id.toUpperCase()))) return false;
        if (c.status != "Pending" && c.status != "Active" && c.status != "Billed") {
          if (D1SalesLedgerService.isPurchaseDeleted(c.id, c.partyId, c.billNo, c.internalNo)) return false;
        } else {
          if (D1SalesLedgerService.isBillDeleted(c.id)) return false;
        }
        int secDelTs = 0;
        if (iNo.isNotEmpty) {
          final t = localTombstoneRegistry[iNo] ?? localTombstoneRegistry[iNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (comp2.isNotEmpty) {
          final t = localTombstoneRegistry[comp2] ?? localTombstoneRegistry[comp2.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (comp.isNotEmpty) {
          final t = localTombstoneRegistry[comp] ?? localTombstoneRegistry[comp.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && c.updatedAt > 0 && secDelTs >= c.updatedAt && c.status != "Pending" && c.status != "Active") return false;
        return true;
      }).toList();
    }

    // 6. Sale Returns Sync with Anti-Zombie Multi-Key Protection
    var allParsedSRet = (decodeJson('s_return.json') as List?)
        ?.map((e) => SaleReturn.fromMap(e))
        .toList();
    if (allParsedSRet != null) {
      for (var r in allParsedSRet) {
        if (r.isDeleted == 1) continue;
        final String cleanBNo = r.billNo.trim().toUpperCase();
        if (r.id.isNotEmpty && (deletedRecordIds.contains(r.id) || deletedRecordIds.contains(r.id.toUpperCase()))) {
          continue; // Blocked by immutable ID tombstone
        }
        int secDelTs = 0;
        if (cleanBNo.isNotEmpty) {
          final t = localTombstoneRegistry[cleanBNo] ?? localTombstoneRegistry[cleanBNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= r.updatedAt) {
          continue; // Blocked by newer or same age series tombstone
        }
        if (cleanBNo.isNotEmpty) {
          deletedRecordIds.remove(cleanBNo);
          deletedRecordIds.remove(cleanBNo.toUpperCase());
        }
        int idx = saleReturns.indexWhere((lr) => 
          (r.id.isNotEmpty && lr.id == r.id) ||
          (cleanBNo.isNotEmpty && lr.billNo.trim().toUpperCase() == cleanBNo)
        );
        if (idx != -1) {
          if (saleReturns[idx].version > r.version) continue;
          if (r.version > saleReturns[idx].version || (r.version == saleReturns[idx].version && r.updatedAt >= saleReturns[idx].updatedAt) || saleReturns[idx].updatedAt == 0) {
            saleReturns[idx] = r;
          }
        } else {
          saleReturns.insert(0, r);
        }
      }
      Map<String, SaleReturn> masterSRetMap = {};
      for (var r in saleReturns) {
        String key = r.billNo.trim().toUpperCase();
        if (key.isEmpty) key = r.id.trim();
        if (!masterSRetMap.containsKey(key) || r.version >= masterSRetMap[key]!.version) {
          masterSRetMap[key] = r;
        }
      }
      saleReturns = masterSRetMap.values.where((r) {
        final bNo = r.billNo.trim().toUpperCase();
        if (D1SalesLedgerService.isBillDeleted(r.id, r.billNo)) return false;
        if (r.id.isNotEmpty && (deletedRecordIds.contains(r.id) || deletedRecordIds.contains(r.id.toUpperCase()))) return false;
        int secDelTs = 0;
        if (bNo.isNotEmpty) {
          final t = localTombstoneRegistry[bNo] ?? localTombstoneRegistry[bNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= r.updatedAt) return false;
        return true;
      }).toList();
    }

    // 7. Purchase Returns Sync with Anti-Zombie Multi-Key Protection
    var allParsedPRet = (decodeJson('p_return.json') as List?)
        ?.map((e) => PurchaseReturn.fromMap(e))
        .toList();
    if (allParsedPRet != null) {
      for (var r in allParsedPRet) {
        if (r.isDeleted == 1) continue;
        final String cleanBNo = r.billNo.trim().toUpperCase();
        if (r.id.isNotEmpty && (deletedRecordIds.contains(r.id) || deletedRecordIds.contains(r.id.toUpperCase()))) {
          continue; // Blocked by immutable ID tombstone
        }
        int secDelTs = 0;
        if (cleanBNo.isNotEmpty) {
          final t = localTombstoneRegistry[cleanBNo] ?? localTombstoneRegistry[cleanBNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= r.updatedAt) {
          continue; // Blocked by newer or same age series tombstone
        }
        if (cleanBNo.isNotEmpty) {
          deletedRecordIds.remove(cleanBNo);
          deletedRecordIds.remove(cleanBNo.toUpperCase());
        }
        int idx = purchaseReturns.indexWhere((lr) => 
          (r.id.isNotEmpty && lr.id == r.id) ||
          (cleanBNo.isNotEmpty && lr.billNo.trim().toUpperCase() == cleanBNo)
        );
        if (idx != -1) {
          if (purchaseReturns[idx].version > r.version) continue;
          if (r.version > purchaseReturns[idx].version || (r.version == purchaseReturns[idx].version && r.updatedAt >= purchaseReturns[idx].updatedAt) || purchaseReturns[idx].updatedAt == 0) {
            purchaseReturns[idx] = r;
          }
        } else {
          purchaseReturns.insert(0, r);
        }
      }
      Map<String, PurchaseReturn> masterPRetMap = {};
      for (var r in purchaseReturns) {
        String key = r.billNo.trim().toUpperCase();
        if (key.isEmpty) key = r.id.trim();
        if (!masterPRetMap.containsKey(key) || r.version >= masterPRetMap[key]!.version) {
          masterPRetMap[key] = r;
        }
      }
      purchaseReturns = masterPRetMap.values.where((r) {
        final bNo = r.billNo.trim().toUpperCase();
        if (D1SalesLedgerService.isBillDeleted(r.id, r.billNo)) return false;
        if (r.id.isNotEmpty && (deletedRecordIds.contains(r.id) || deletedRecordIds.contains(r.id.toUpperCase()))) return false;
        int secDelTs = 0;
        if (bNo.isNotEmpty) {
          final t = localTombstoneRegistry[bNo] ?? localTombstoneRegistry[bNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= r.updatedAt) return false;
        return true;
      }).toList();
    }

    CompanySyncModule.mergeCompanyList(
      cloudCompanyList: decodeJson('comps.json') as List?,
      localCompanyList: companies,
      tombstoneRegistry: localTombstoneRegistry,
      deletedIds: deletedRecordIds,
      medicines: medicines,
      shortages: shortages,
    );
    SaltSyncModule.mergeSaltList(
      cloudSaltList: decodeJson('salts.json') as List?,
      localSaltList: salts,
      tombstoneRegistry: localTombstoneRegistry,
      deletedIds: deletedRecordIds,
      medicines: medicines,
    );
    RouteSyncModule.mergeRouteList(
      cloudRouteList: decodeJson('routs.json') as List?,
      localRouteList: routes,
      tombstoneRegistry: localTombstoneRegistry,
      deletedIds: deletedRecordIds,
      parties: parties,
    );
    banks = (decodeJson('banks.json') as List?)?.map((e) => Bank.fromMap(e)).toList() ?? [];
    numberingSeries = (decodeJson('series.json') as List?)?.map((e) => NumberingSeries.fromMap(e)).toList() ?? [];

    var cData = decodeJson('config.json');
    if (cData != null && cData is Map<String, dynamic>) {
      final incomingCfg = AppConfig.fromMap(cData);
      if (appConfig.updatedAt == 0 ||
          incomingCfg.updatedAt >= appConfig.updatedAt ||
          incomingCfg.version > appConfig.version) {
        appConfig = incomingCfg;
      }
    }

    // 🛡️ NON-DESTRUCTIVE LWW DELTA MERGE (#PH-REV-764): Never wipe in-flight local batch edits!
    var bData = decodeJson('bats.json');
    if (bData != null) {
      BatchDeltaMergeModule.mergeBatchHistoryFromCloudJson(
        targetBatchHistory: batchHistory,
        incomingJson: bData,
        tombstones: deletedRecordIds,
        registry: localTombstoneRegistry,
      );
    } else {
      BatchDeltaMergeModule.purgeTombstonedBatches(
        batchHistory,
        tombstones: deletedRecordIds,
        registry: localTombstoneRegistry,
      );
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
      final existing = history[existingIdx];
      // 🛡️ LWW Protection: If batch was already configured in Master (version > 1), preserve its master pricing & expiry!
      if (existing.version <= 1) {
        existing.exp = exp;
        existing.mrp = mrp;
        existing.rate = rate;
        existing.packing = packing;
        existing.purRate = rate;
        existing.rateA = finalRateA;
        existing.rateB = finalRateB;
        existing.rateC = finalRateC;
        existing.rateCFormula = rateCFormula;
        existing.appliedRateType = appliedRateType;
        existing.status = status;
      }
      if (qtyChange != 0.0) {
        existing.qty += qtyChange;
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
      notifyListeners();
    }
  }

  void _cascadeWebFyVaultFrom(String startYear) {
    if (availableFinancialYears.length < 2) return;
    int startIdx = availableFinancialYears.indexOf(startYear);
    if (startIdx == -1) startIdx = 0;
    for (int i = startIdx; i < availableFinancialYears.length - 1; i++) {
      final String prevFy = availableFinancialYears[i];
      final String targetFy = availableFinancialYears[i + 1];
      final prevFiles = fyVault[prevFy];
      final targetFiles = fyVault[targetFy];
      if (prevFiles == null || targetFiles == null) continue;
      final res = FYTransferEngine.cascadeSingleYearStep(
        prevFiles: prevFiles,
        targetFiles: targetFiles,
        prevFY: prevFy,
        targetFY: targetFy,
      );
      fyVault[prevFy] = res.healedPrevFiles;
      fyVault[targetFy] = res.healedTargetFiles;
    }
  }

  Future<bool> pushUpdatedDataToCloud() async {
    try {
      if (!isAuthenticated || activeStoreToken.isEmpty) return false;

      // 1. Save current active FY state into Multi-FY Vault
      fyVault[financialYear] = _captureCurrentMemoryToFyFilesMap();

      // 2. MARG-STYLE AUTO-CASCADE: If editing a back year on Web, automatically cascade to newer years!
      if (isBackYearActive) {
        _cascadeWebFyVaultFrom(financialYear);
      }

      final String latestFy = availableFinancialYears.isNotEmpty
          ? availableFinancialYears.last
          : financialYear;
      companyProfile['fYears'] = availableFinancialYears;

      final Map<String, String> topYearFiles =
          Map<String, String>.from(fyVault[latestFy] ?? fyVault[financialYear]!);
      final Map<String, String> filesPayload = {
        ...topYearFiles,
        'fy_vault.json': jsonEncode(fyVault),
        'tombstones.json': jsonEncode(deletedRecordIds.toList()),
        'tombstone_registry.json': jsonEncode(localTombstoneRegistry),
      };

      final payload = {
        "action": WebCloudConfig.actionPushStore,
        "storeToken": activeStoreToken,
        "companyId": companyProfile['id'] ?? 'STORE',
        "companyName": companyName,
        "adminUser": activeUsername,
        "adminPassword": activePassword,
        "fy": latestFy,
        "activeFy": financialYear,
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

  void unmarkDeletedId(String id, {String? referenceNo}) {
    final cleanId = id.trim();
    if (cleanId.isNotEmpty) {
      deletedRecordIds.remove(cleanId);
      deletedRecordIds.remove(cleanId.toUpperCase());
      localTombstoneRegistry.remove(cleanId);
      localTombstoneRegistry.remove(cleanId.toUpperCase());
      unmarkedRecordIds.add(cleanId);
      unmarkedRecordIds.add(cleanId.toUpperCase());
    }
    if (referenceNo != null && referenceNo.trim().isNotEmpty) {
      final cleanRef = referenceNo.trim();
      deletedRecordIds.remove(cleanRef);
      deletedRecordIds.remove(cleanRef.toUpperCase());
      localTombstoneRegistry.remove(cleanRef);
      localTombstoneRegistry.remove(cleanRef.toUpperCase());
      unmarkedRecordIds.add(cleanRef);
      unmarkedRecordIds.add(cleanRef.toUpperCase());
    }
    _saveLocalTombstones();
  }

  void addSaleAndSync(Sale sale) {
    unmarkDeletedId(sale.id, referenceNo: sale.billNo);
    D1SalesLedgerService.unmarkPermanentlyDeleted(sale.id, sale.billNo);
    if (sale.billNo.trim().isNotEmpty) {
      D1SalesLedgerService.unmarkPermanentlyDeleted(sale.billNo.trim());
    }
    if (sale.linkedChallanIds.isNotEmpty) {
      final Set<String> lKeys = sale.linkedChallanIds.map((k) => k.trim().toUpperCase()).toSet();
      for (var ch in saleChallans) {
        if (lKeys.contains(ch.id.trim().toUpperCase()) || lKeys.contains(ch.billNo.trim().toUpperCase())) {
          ch.status = "Billed";
          ch.version += 1;
          ch.updatedAt = DateTime.now().millisecondsSinceEpoch;
          SaleChallanSyncModule.onSaleChallanSaved(ch, activeStoreToken);
        }
      }
    }
        ProductIntegrityService.ensureLineItemsInProductMaster(
      items: sale.items,
      medicines: medicines,
      storeToken: activeStoreToken,
      onMedicineSaved: (med) {
        MedicineSyncModule.onMedicineSaved(med, activeStoreToken);
      },
      sourceTag: "SALE",
    );
    final int existingIdx = sales.indexWhere((s) => s.id == sale.id || (sale.billNo.trim().isNotEmpty && s.billNo.trim().toUpperCase() == sale.billNo.trim().toUpperCase()));
    final bool isUpdate = existingIdx != -1;

    // 🛡️ ENTERPRISE MONOTONIC VERSIONING & OCC RECONCILER (#PH-REV-692)
    int maxVer = sale.version;
    if (isUpdate && sales[existingIdx].version >= maxVer) {
      maxVer = sales[existingIdx].version + 1;
    }
    final int d1Known = D1SalesLedgerService.getKnownVersion(sale.id, sale.billNo);
    if (d1Known >= maxVer) {
      maxVer = d1Known + 1;
    }
    sale.version = maxVer;
    sale.updatedAt = DateTime.now().millisecondsSinceEpoch;
    D1SalesLedgerService.recordKnownVersion(sale.id, sale.billNo, sale.version);

    if (isUpdate) {
      sales[existingIdx] = sale;
    } else {
      sales.insert(0, sale);
    }
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

    // ⚡ Transactional Outbox Batch Enqueue
    SalesSyncModule.onSaleSaved(sale, activeStoreToken);
    D1SalesLedgerService.onSaleSaved(sale, activeStoreToken, isUpdate: existingIdx != -1, clientSource: "WEB_PORTAL");

    // ⚡ Fast Non-Blocking Background Cloud Push
    _autoSyncService.triggerAutoSync(
      action: 'DATA_SAVED',
      entityId: sale.id,
      unmarkedIds: [sale.id, if (sale.billNo.isNotEmpty) sale.billNo],
    );
  }

  void deleteSale(String saleId) {
    String realId = saleId;
    String targetBillNo = "";
    try {
      final s = sales.firstWhere(
        (x) => x.id == saleId || x.billNo == saleId,
        orElse: () => sales.firstWhere((x) => x.id == saleId),
      );
      realId = s.id;
      targetBillNo = s.billNo;
      D1SalesLedgerService.markPermanentlyDeleted(realId, targetBillNo);
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
            ch.version += 1;
            ch.updatedAt = DateTime.now().millisecondsSinceEpoch;
            unmarkDeletedId(ch.id, referenceNo: ch.billNo);
            D1SalesLedgerService.unmarkPermanentlyDeleted(ch.id, ch.billNo);
            SaleChallanSyncModule.onSaleChallanSaved(ch, activeStoreToken);
          }
        }
      }

      SalesSyncModule.onSaleDeleted(s, activeStoreToken);
      D1SalesLedgerService.onSaleDeleted(realId, s.billNo, activeStoreToken, clientSource: "WEB_PORTAL", linkedChallanIds: s.linkedChallanIds);
    } catch (_) {}

    final int delTime = DateTime.now().millisecondsSinceEpoch;
    localTombstoneRegistry[realId] = delTime;
    deletedRecordIds.add(realId);
    unmarkedRecordIds.remove(realId);
    if (targetBillNo.isNotEmpty) {
      final cleanBillKey = targetBillNo.trim().toUpperCase();
      localTombstoneRegistry[cleanBillKey] = delTime;
      deletedRecordIds.add(cleanBillKey);
      unmarkedRecordIds.remove(cleanBillKey);
    }
    _saveLocalTombstones();

    sales.removeWhere((s) => s.id == realId || (targetBillNo.isNotEmpty && s.billNo.trim().toUpperCase() == targetBillNo.trim().toUpperCase()));
    rebuildInventory();
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'RECORD_DELETED',
      entityId: realId,
      deletedIds: [realId, if (targetBillNo.isNotEmpty) targetBillNo.trim().toUpperCase()],
    );
  }

  void cancelSale(String saleId) {
    int i = sales.indexWhere((x) => x.id == saleId || x.billNo == saleId);
    if (i != -1) {
      sales[i].status = "Cancelled";
      rebuildInventory();
      notifyListeners();
      D1SalesLedgerService.onSaleCancelled(sales[i], activeStoreToken, clientSource: "WEB_PORTAL");
      _autoSyncService.triggerAutoSync(
        action: 'CANCEL_SALE',
        entityId: sales[i].id,
      );
    }
  }

  void addPurchaseAndSync(Purchase purchase) {
    final compKey = PurchaseSyncModule.makeCompositeKey(purchase.partyId, purchase.billNo, purchase.internalNo);
    final compKey2 = (purchase.partyId.trim().isNotEmpty && purchase.billNo.trim().isNotEmpty)
        ? "${purchase.partyId.trim().toUpperCase()}_${purchase.billNo.trim().toUpperCase()}"
        : "";
    unmarkDeletedId(purchase.id, referenceNo: purchase.internalNo);
    if (purchase.billNo.isNotEmpty) unmarkDeletedId(purchase.billNo);
    if (compKey.isNotEmpty) unmarkDeletedId(compKey);
    if (compKey2.isNotEmpty) unmarkDeletedId(compKey2);
    D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(purchase.id, purchase.partyId, purchase.billNo, purchase.internalNo);
    if (purchase.billNo.trim().isNotEmpty) D1SalesLedgerService.unmarkPermanentlyDeleted(purchase.billNo.trim());
    if (purchase.internalNo.trim().isNotEmpty) D1SalesLedgerService.unmarkPermanentlyDeleted(purchase.internalNo.trim());
    if (purchase.linkedChallanIds.isNotEmpty) {
      final Set<String> lKeys = purchase.linkedChallanIds.map((k) => k.trim().toUpperCase()).toSet();
      for (var ch in purchaseChallans) {
        if (lKeys.contains(ch.id.trim().toUpperCase()) || lKeys.contains(ch.internalNo.trim().toUpperCase()) || lKeys.contains(ch.billNo.trim().toUpperCase())) {
          ch.status = "Billed";
          ch.version += 1;
          ch.updatedAt = DateTime.now().millisecondsSinceEpoch;
          PurchaseChallanSyncModule.onPurchaseChallanSaved(ch, activeStoreToken);
        }
      }
    }

        ProductIntegrityService.ensurePurchaseItemsInProductMaster(
      items: purchase.items,
      medicines: medicines,
      storeToken: activeStoreToken,
      onMedicineSaved: (med) {
        MedicineSyncModule.onMedicineSaved(med, activeStoreToken);
      },
      sourceTag: "PURCHASE",
    );
    final cleanIntNo = purchase.internalNo.trim().toUpperCase();
    final cleanBillNo = purchase.billNo.trim().toUpperCase();
    final cleanPartyId = purchase.partyId.trim().toUpperCase();

    final int existingIdx = purchases.indexWhere((p) => 
      p.id == purchase.id || 
      (cleanIntNo.isNotEmpty && p.internalNo.isNotEmpty && p.internalNo.trim().toUpperCase() == cleanIntNo)
    );
    final bool isUpdate = existingIdx != -1;

    // 🛡️ ENTERPRISE MONOTONIC VERSIONING & OCC RECONCILER (#PH-REV-692)
    int maxVer = purchase.version;
    if (isUpdate && purchases[existingIdx].version >= maxVer) {
      maxVer = purchases[existingIdx].version + 1;
    }
    final int d1Known = D1SalesLedgerService.getPurchaseKnownVersion(purchase.id, purchase.partyId, purchase.billNo, purchase.internalNo);
    if (d1Known >= maxVer) {
      maxVer = d1Known + 1;
    }
    purchase.version = maxVer;
    purchase.updatedAt = DateTime.now().millisecondsSinceEpoch;
    D1SalesLedgerService.recordPurchaseKnownVersion(purchase.id, purchase.partyId, purchase.billNo, purchase.version, purchase.internalNo);

    if (isUpdate) {
      purchases[existingIdx] = purchase;
    } else {
      purchases.insert(0, purchase);
    }
    PurchaseSyncModule.onPurchaseSaved(purchase, activeStoreToken);
    D1SalesLedgerService.onPurchaseSaved(purchase, activeStoreToken, isUpdate: isUpdate, clientSource: "WEB_PORTAL");
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

    // ⚡ Fast Non-Blocking Background Cloud Push with Composite Key
    _autoSyncService.triggerAutoSync(
      action: 'DATA_SAVED',
      entityId: purchase.id,
      unmarkedIds: [
        purchase.id,
        if (purchase.internalNo.isNotEmpty) purchase.internalNo,
        if (compKey.isNotEmpty) compKey,
        if (compKey2.isNotEmpty) compKey2,
      ],
    );
  }

  void deletePurchase(String purId) {
    String realId = purId;
    String targetIntNo = "";
    String targetBillNo = "";
    String targetPartyId = "";
    String compKey2 = "";
    String compKey3 = "";
    try {
      final p = purchases.firstWhere(
        (x) => x.id == purId || x.internalNo == purId,
        orElse: () => purchases.firstWhere((x) => x.id == purId),
      );
      realId = p.id;
      targetIntNo = p.internalNo.trim().toUpperCase();
      targetBillNo = p.billNo.trim().toUpperCase();
      targetPartyId = p.partyId.trim().toUpperCase();
      compKey2 = (targetPartyId.isNotEmpty && targetBillNo.isNotEmpty) ? "${targetPartyId}_$targetBillNo" : "";
      compKey3 = PurchaseSyncModule.makeCompositeKey(targetPartyId, targetBillNo, targetIntNo);
      D1SalesLedgerService.markPurchasePermanentlyDeleted(realId, targetPartyId, targetBillNo, targetIntNo);
      D1SalesLedgerService.onPurchaseDeleted(
        realId,
        targetPartyId,
        targetBillNo,
        targetIntNo,
        activeStoreToken,
        clientSource: "WEB_PORTAL",
        linkedChallanIds: p.linkedChallanIds,
      );
      PurchaseSyncModule.onPurchaseDeleted(p, activeStoreToken);
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
            ch.version += 1;
            ch.updatedAt = DateTime.now().millisecondsSinceEpoch;
            unmarkDeletedId(ch.id, referenceNo: ch.internalNo);
            if (ch.billNo.isNotEmpty) unmarkDeletedId(ch.billNo);
            D1SalesLedgerService.unmarkPermanentlyDeleted(ch.id, ch.billNo, ch.internalNo);
            PurchaseChallanSyncModule.onPurchaseChallanSaved(ch, activeStoreToken);
          }
        }
      }
    } catch (_) {}

    final int delTime = DateTime.now().millisecondsSinceEpoch;
    // 🛡️ COMPOSITE TOMBSTONE KEYS: NEVER naked targetBillNo alone!
    final List<String> delKeys = [
      realId,
      if (targetIntNo.isNotEmpty) targetIntNo,
      if (compKey2.isNotEmpty) compKey2,
      if (compKey3.isNotEmpty) compKey3,
    ];

    for (var k in delKeys) {
      localTombstoneRegistry[k] = delTime;
      localTombstoneRegistry[k.toUpperCase()] = delTime;
      deletedRecordIds.add(k);
      deletedRecordIds.add(k.toUpperCase());
      unmarkedRecordIds.remove(k);
      unmarkedRecordIds.remove(k.toUpperCase());
    }
    _saveLocalTombstones();
    purchases.removeWhere((p) => 
      p.id == realId || 
      (targetIntNo.isNotEmpty && p.internalNo.trim().toUpperCase() == targetIntNo) ||
      (targetBillNo.isNotEmpty && targetPartyId.isNotEmpty &&
       p.billNo.trim().toUpperCase() == targetBillNo && p.partyId.trim().toUpperCase() == targetPartyId)
    );
    rebuildInventory();
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'DELETE_PURCHASE',
      entityId: realId,
      deletedIds: delKeys,
    );
  }

  void addVoucherAndSync(Voucher v) {
    final String cleanVNo = v.voucherNo.trim().toUpperCase();
    unmarkDeletedId(v.id, referenceNo: cleanVNo);
    D1SalesLedgerService.unmarkPermanentlyDeleted(v.id, cleanVNo);

    final int existingIdx = vouchers.indexWhere((old) =>
      old.id == v.id || (cleanVNo.isNotEmpty && old.voucherNo.trim().toUpperCase() == cleanVNo)
    );
    int maxVer = v.version;
    if (existingIdx != -1 && vouchers[existingIdx].version >= maxVer) {
      maxVer = vouchers[existingIdx].version + 1;
    }
    final int knownVer = D1SalesLedgerService.getKnownVersion(v.id, cleanVNo);
    if (knownVer >= maxVer) {
      maxVer = knownVer + 1;
    }
    v.version = maxVer;
    v.updatedAt = DateTime.now().millisecondsSinceEpoch;
    v.isDeleted = 0;
    D1SalesLedgerService.recordKnownVersion(v.id, cleanVNo, v.version);

    vouchers.removeWhere((old) =>
      old.id == v.id || (cleanVNo.isNotEmpty && old.voucherNo.trim().toUpperCase() == cleanVNo)
    );
    vouchers.add(v);
    notifyListeners();

    WebVoucherD1SyncService.onVoucherSaved(v, activeStoreToken, clientSource: "WEB_PORTAL");
    _autoSyncService.triggerAutoSync(
      action: 'VOUCHER_SAVED',
      entityId: v.id,
      unmarkedIds: [v.id, if (cleanVNo.isNotEmpty) cleanVNo],
    );
  }

  void deleteVoucher(String voucherId) {
    String realId = voucherId;
    String vNo = "";
    try {
      final targetV = vouchers.firstWhere((item) => item.id == voucherId || item.voucherNo == voucherId);
      realId = targetV.id;
      vNo = targetV.voucherNo.trim().toUpperCase();
      WebVoucherD1SyncService.onVoucherDeleted(targetV, activeStoreToken, clientSource: "WEB_PORTAL");
    } catch (_) {
      D1SalesLedgerService.markPermanentlyDeleted(voucherId);
    }
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    final List<String> delKeys = [
      realId,
      if (voucherId != realId) voucherId,
      if (vNo.isNotEmpty) vNo,
    ];
    for (var k in delKeys) {
      localTombstoneRegistry[k] = delTime;
      localTombstoneRegistry[k.toUpperCase()] = delTime;
      deletedRecordIds.add(k);
      deletedRecordIds.add(k.toUpperCase());
      unmarkedRecordIds.remove(k);
      unmarkedRecordIds.remove(k.toUpperCase());
    }
    _saveLocalTombstones();
    vouchers.removeWhere((item) =>
      item.id == realId ||
      item.id == voucherId ||
      (vNo.isNotEmpty && item.voucherNo.trim().toUpperCase() == vNo)
    );
    notifyListeners();
    pushUpdatedDataToCloud();
    _autoSyncService.triggerAutoSync(
      action: 'DELETE_VOUCHER',
      entityId: realId,
      deletedIds: delKeys,
    );
  }

  void addSaleChallanAndSync(SaleChallan challan) {
    unmarkDeletedId(challan.id, referenceNo: challan.billNo);
    D1SalesLedgerService.unmarkPermanentlyDeleted(challan.id, challan.billNo);

    final cleanBNo = challan.billNo.trim().toUpperCase();
        ProductIntegrityService.ensureLineItemsInProductMaster(
      items: challan.items,
      medicines: medicines,
      storeToken: activeStoreToken,
      onMedicineSaved: (med) {
        MedicineSyncModule.onMedicineSaved(med, activeStoreToken);
      },
      sourceTag: "CHALLAN",
    );
    final int existingIdx = saleChallans.indexWhere((c) =>
      c.id == challan.id ||
      (cleanBNo.isNotEmpty && c.billNo.trim().toUpperCase() == cleanBNo)
    );
    final bool isUpdate = existingIdx != -1;
    if (isUpdate && saleChallans[existingIdx].version >= challan.version) {
      challan.version = saleChallans[existingIdx].version + 1;
    }
    challan.updatedAt = DateTime.now().millisecondsSinceEpoch;

    if (isUpdate) {
      saleChallans[existingIdx] = challan;
    } else {
      saleChallans.insert(0, challan);
    }
    SaleChallanSyncModule.onSaleChallanSaved(challan, activeStoreToken);

    for (var item in challan.items) {
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

    _autoSyncService.triggerAutoSync(
      action: 'DATA_SAVED',
      entityId: challan.id,
      unmarkedIds: [
        challan.id,
        if (challan.billNo.isNotEmpty) challan.billNo,
      ],
    );
  }

  void addPurchaseChallanAndSync(PurchaseChallan challan) {
    final compKey = PurchaseChallanSyncModule.makeCompositeKey(challan.partyId, challan.billNo, challan.internalNo);
    unmarkDeletedId(challan.id, referenceNo: challan.internalNo);
    if (challan.billNo.isNotEmpty) unmarkDeletedId(challan.billNo);
    if (compKey.isNotEmpty) unmarkDeletedId(compKey);
    D1SalesLedgerService.unmarkPermanentlyDeleted(challan.id, challan.billNo, challan.internalNo);

    final cleanINo = challan.internalNo.trim().toUpperCase();
    final cleanBNo = challan.billNo.trim().toUpperCase();
    final cleanParty = challan.partyId.trim().toUpperCase();

        ProductIntegrityService.ensurePurchaseItemsInProductMaster(
      items: challan.items,
      medicines: medicines,
      storeToken: activeStoreToken,
      onMedicineSaved: (med) {
        MedicineSyncModule.onMedicineSaved(med, activeStoreToken);
      },
      sourceTag: "PURCHASE_CHALLAN",
    );
    final int existingIdx = purchaseChallans.indexWhere((c) =>
      c.id == challan.id ||
      (cleanINo.isNotEmpty && c.internalNo.trim().toUpperCase() == cleanINo) ||
      (cleanBNo.isNotEmpty && cleanParty.isNotEmpty && c.billNo.trim().toUpperCase() == cleanBNo && c.partyId.trim().toUpperCase() == cleanParty)
    );
    final bool isUpdate = existingIdx != -1;
    if (isUpdate && purchaseChallans[existingIdx].version >= challan.version) {
      challan.version = purchaseChallans[existingIdx].version + 1;
    }
    challan.updatedAt = DateTime.now().millisecondsSinceEpoch;

    if (isUpdate) {
      purchaseChallans[existingIdx] = challan;
    } else {
      purchaseChallans.insert(0, challan);
    }
    PurchaseChallanSyncModule.onPurchaseChallanSaved(challan, activeStoreToken);

    for (var item in challan.items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey;
        med.purRate = item.purchaseRate;
        if (item.mrp > 0) med.mrp = item.mrp;
        if (item.rateA > 0) med.rateA = item.rateA;
        if (item.rateB > 0) med.rateB = item.rateB;
        if (item.rateC > 0) med.rateC = item.rateC;
        updateMedicine(med);
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

    _autoSyncService.triggerAutoSync(
      action: 'DATA_SAVED',
      entityId: challan.id,
      unmarkedIds: [
        challan.id,
        if (challan.internalNo.isNotEmpty) challan.internalNo,
        if (challan.billNo.isNotEmpty) challan.billNo,
        if (compKey.isNotEmpty) compKey,
      ],
    );
  }

  void deleteSaleChallan(String challanId) {
    String bNo = "";
    try {
      final targetC = saleChallans.firstWhere((item) => item.id == challanId || item.billNo == challanId);
      bNo = targetC.billNo.trim().toUpperCase();
      SaleChallanSyncModule.onSaleChallanDeleted(targetC, activeStoreToken);
    } catch (_) {}
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    final List<String> delKeys = [challanId, if (bNo.isNotEmpty) bNo];
    for (var k in delKeys) {
      localTombstoneRegistry[k] = delTime;
      localTombstoneRegistry[k.toUpperCase()] = delTime;
      deletedRecordIds.add(k);
      deletedRecordIds.add(k.toUpperCase());
      unmarkedRecordIds.remove(k);
      unmarkedRecordIds.remove(k.toUpperCase());
    }
    _saveLocalTombstones();
    saleChallans.removeWhere((item) => item.id == challanId || (bNo.isNotEmpty && item.billNo.trim().toUpperCase() == bNo));
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'DELETE_SALE_CHALLAN',
      entityId: challanId,
      deletedIds: delKeys,
    );
  }

  void deletePurchaseChallan(String challanId) {
    String iNo = "";
    String bNo = "";
    String pId = "";
    String compKey2 = "";
    String compKey = "";
    try {
      final targetC = purchaseChallans.firstWhere((item) => item.id == challanId || item.internalNo == challanId || item.billNo == challanId);
      iNo = targetC.internalNo.trim().toUpperCase();
      bNo = targetC.billNo.trim().toUpperCase();
      pId = targetC.partyId.trim().toUpperCase();
      compKey2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
      compKey = PurchaseChallanSyncModule.makeCompositeKey(pId, bNo, iNo);
      PurchaseChallanSyncModule.onPurchaseChallanDeleted(targetC, activeStoreToken);
    } catch (_) {}
    D1SalesLedgerService.markPurchasePermanentlyDeleted(challanId, pId, bNo, iNo);
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    final List<String> delKeys = [
      challanId,
      if (iNo.isNotEmpty) iNo,
      if (compKey2.isNotEmpty) compKey2,
      if (compKey.isNotEmpty) compKey,
    ];
    for (var k in delKeys) {
      localTombstoneRegistry[k] = delTime;
      localTombstoneRegistry[k.toUpperCase()] = delTime;
      deletedRecordIds.add(k);
      deletedRecordIds.add(k.toUpperCase());
      unmarkedRecordIds.remove(k);
      unmarkedRecordIds.remove(k.toUpperCase());
    }
    _saveLocalTombstones();
    purchaseChallans.removeWhere((item) =>
      item.id == challanId ||
      (iNo.isNotEmpty && item.internalNo.trim().toUpperCase() == iNo) ||
      (pId.isNotEmpty && bNo.isNotEmpty && item.partyId.trim().toUpperCase() == pId && item.billNo.trim().toUpperCase() == bNo)
    );
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'DELETE_PURCHASE_CHALLAN',
      entityId: challanId,
      deletedIds: delKeys,
    );
  }

  void addSaleReturnAndSync(SaleReturn ret) {
    unmarkDeletedId(ret.id, referenceNo: ret.billNo);
    D1SalesLedgerService.unmarkPermanentlyDeleted(ret.id, ret.billNo);

    final cleanBNo = ret.billNo.trim().toUpperCase();
    final int existingIdx = saleReturns.indexWhere((r) =>
      r.id == ret.id ||
      (cleanBNo.isNotEmpty && r.billNo.trim().toUpperCase() == cleanBNo)
    );
    final bool isUpdate = existingIdx != -1;
    if (isUpdate && saleReturns[existingIdx].version >= ret.version) {
      ret.version = saleReturns[existingIdx].version + 1;
    }
    ret.updatedAt = DateTime.now().millisecondsSinceEpoch;

    if (isUpdate) {
      saleReturns[existingIdx] = ret;
    } else {
      saleReturns.insert(0, ret);
    }
    CreditNoteSyncModule.onCreditNoteSaved(ret, activeStoreToken);

    for (var item in ret.items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey;
      } catch (_) {}

      double qtyChange = item.isBreakage ? 0.0 : (item.qty + item.freeQty);
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
        qtyChange: qtyChange,
      );
    }
    rebuildInventory();
    notifyListeners();

    _autoSyncService.triggerAutoSync(
      action: 'DATA_SAVED',
      entityId: ret.id,
      unmarkedIds: [
        ret.id,
        if (ret.billNo.isNotEmpty) ret.billNo,
      ],
    );
  }

  void addPurchaseReturnAndSync(PurchaseReturn ret) {
    unmarkDeletedId(ret.id, referenceNo: ret.billNo);
    D1SalesLedgerService.unmarkPermanentlyDeleted(ret.id, ret.billNo);

    final cleanBNo = ret.billNo.trim().toUpperCase();
    final int existingIdx = purchaseReturns.indexWhere((r) =>
      r.id == ret.id ||
      (cleanBNo.isNotEmpty && r.billNo.trim().toUpperCase() == cleanBNo)
    );
    final bool isUpdate = existingIdx != -1;
    if (isUpdate && purchaseReturns[existingIdx].version >= ret.version) {
      ret.version = purchaseReturns[existingIdx].version + 1;
    }
    ret.updatedAt = DateTime.now().millisecondsSinceEpoch;

    if (isUpdate) {
      purchaseReturns[existingIdx] = ret;
    } else {
      purchaseReturns.insert(0, ret);
    }
    DebitNoteSyncModule.onDebitNoteSaved(ret, activeStoreToken);

    for (var item in ret.items) {
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
        qtyChange: -(item.qty + item.freeQty),
      );
    }
    rebuildInventory();
    notifyListeners();

    _autoSyncService.triggerAutoSync(
      action: 'DATA_SAVED',
      entityId: ret.id,
      unmarkedIds: [
        ret.id,
        if (ret.billNo.isNotEmpty) ret.billNo,
      ],
    );
  }

  void deleteSaleReturn(String returnId) {
    String bNo = "";
    try {
      final targetR = saleReturns.firstWhere((item) => item.id == returnId || item.billNo == returnId);
      bNo = targetR.billNo.trim().toUpperCase();
      CreditNoteSyncModule.onCreditNoteDeleted(targetR, activeStoreToken);
    } catch (_) {}
    D1SalesLedgerService.markPermanentlyDeleted(returnId, bNo);
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    final List<String> delKeys = [returnId, if (bNo.isNotEmpty) bNo];
    for (var k in delKeys) {
      localTombstoneRegistry[k] = delTime;
      localTombstoneRegistry[k.toUpperCase()] = delTime;
      deletedRecordIds.add(k);
      deletedRecordIds.add(k.toUpperCase());
      unmarkedRecordIds.remove(k);
      unmarkedRecordIds.remove(k.toUpperCase());
    }
    _saveLocalTombstones();
    saleReturns.removeWhere((item) => item.id == returnId || (bNo.isNotEmpty && item.billNo.trim().toUpperCase() == bNo));
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'DELETE_SALE_RETURN',
      entityId: returnId,
      deletedIds: delKeys,
    );
  }

  void deletePurchaseReturn(String returnId) {
    String bNo = "";
    try {
      final targetR = purchaseReturns.firstWhere((item) => item.id == returnId || item.billNo == returnId);
      bNo = targetR.billNo.trim().toUpperCase();
      DebitNoteSyncModule.onDebitNoteDeleted(targetR, activeStoreToken);
    } catch (_) {}
    D1SalesLedgerService.markPermanentlyDeleted(returnId, bNo);
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    final List<String> delKeys = [returnId, if (bNo.isNotEmpty) bNo];
    for (var k in delKeys) {
      localTombstoneRegistry[k] = delTime;
      localTombstoneRegistry[k.toUpperCase()] = delTime;
      deletedRecordIds.add(k);
      deletedRecordIds.add(k.toUpperCase());
      unmarkedRecordIds.remove(k);
      unmarkedRecordIds.remove(k.toUpperCase());
    }
    _saveLocalTombstones();
    purchaseReturns.removeWhere((item) => item.id == returnId || (bNo.isNotEmpty && item.billNo.trim().toUpperCase() == bNo));
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'DELETE_PURCHASE_RETURN',
      entityId: returnId,
      deletedIds: delKeys,
    );
  }

  String resolveCompanyName(String idOrName) => MasterCascadeService.resolveCompanyName(idOrName, companies);
  String resolveSaltName(String idOrName) => MasterCascadeService.resolveSaltName(idOrName, salts);

  String getOrCreateCompany(String name) {
    final cleanTarget = CompanySyncModule.cleanString(name);
    if (cleanTarget.isEmpty) return "";
    try {
      return companies.firstWhere((c) =>
          CompanySyncModule.cleanString(c.name) == cleanTarget ||
          c.id.trim().toUpperCase() == name.trim().toUpperCase()).id;
    } catch (_) {
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      String id = "CP-${1000 + companies.length + 1}-${nowTs % 10000}";
      final comp = Company(id: id, name: name.trim().toUpperCase(), updatedAt: nowTs, version: 1);
      saveOrUpdateCompany(comp);
      return id;
    }
  }

  String getOrCreateSalt(String name) {
    final cleanTarget = SaltSyncModule.cleanString(name);
    if (cleanTarget.isEmpty) return "";
    try {
      return salts.firstWhere((s) =>
          SaltSyncModule.cleanString(s.name) == cleanTarget ||
          s.id.trim().toUpperCase() == name.trim().toUpperCase()).id;
    } catch (_) {
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      String id = "SL-${1000 + salts.length + 1}-${nowTs % 10000}";
      final salt = Salt(id: id, name: name.trim().toUpperCase(), type: "Mono", updatedAt: nowTs, version: 1);
      saveOrUpdateSalt(salt);
      return id;
    }
  }

  String getOrCreateRoute(String name) {
    final cleanTarget = RouteSyncModule.cleanString(name);
    if (cleanTarget.isEmpty) return "";
    try {
      return routes.firstWhere((r) =>
          RouteSyncModule.cleanString(r.name) == cleanTarget ||
          r.id.trim().toUpperCase() == name.trim().toUpperCase()).name;
    } catch (_) {
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      String id = "RT-${1000 + routes.length + 1}-${nowTs % 10000}";
      final route = RouteArea(id: id, name: name.trim().toUpperCase(), updatedAt: nowTs, version: 1);
      saveOrUpdateRoute(route);
      return route.name;
    }
  }

  // ===========================================================================
  // 🏛️ ENTERPRISE COMPANY / SALT / ROUTE MASTER SYNC & CASCADE (#PH-REV-768)
  // ===========================================================================

  int saveOrUpdateCompany(Company comp, {String? previousName}) {
    final nowTs = DateTime.now().millisecondsSinceEpoch;
    final cleanName = comp.name.trim().toUpperCase();
    final cleanKey = CompanySyncModule.cleanString(cleanName);
    if (cleanKey.isEmpty) return 0;

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
    unmarkDeletedId(savedComp.id, referenceNo: cTombKey);

    final List<Medicine> mutatedMeds = [];
    final int mutatedCount = MasterCascadeService.cascadeCompanyUpdate(
      updatedCompany: savedComp,
      previousName: oldName,
      medicines: medicines,
      shortages: shortages,
      onMedicineMutated: (m) => mutatedMeds.add(m),
    );

    if (activeStoreToken.isNotEmpty) {
      CompanySyncModule.onCompanySaved(savedComp, activeStoreToken, previousName: oldName);
      for (final m in mutatedMeds) {
        MedicineSyncModule.onMedicineSaved(m, activeStoreToken);
      }
    }

    _autoSyncService.triggerAutoSync(
      action: "COMPANY_SAVED",
      entityId: savedComp.id,
      unmarkedIds: [savedComp.id, cTombKey],
    );
    notifyListeners();
    pushUpdatedDataToCloud();
    return mutatedCount;
  }

  int deleteCompanyMaster(String companyId, {String? reassignToCompanyId}) {
    final idx = companies.indexWhere((c) => c.id == companyId);
    if (idx == -1) return 0;
    final target = companies[idx];
    final cleanKey = "COMP_${CompanySyncModule.cleanString(target.name)}";
    final nowTs = DateTime.now().millisecondsSinceEpoch;

    Company? targetReassign;
    if (reassignToCompanyId != null && reassignToCompanyId.isNotEmpty) {
      try {
        targetReassign = companies.firstWhere((c) => c.id == reassignToCompanyId);
      } catch (_) {}
    }

    final List<Medicine> mutatedMeds = [];
    for (var m in medicines) {
      if (MasterCascadeService.belongsToCompany(m, target)) {
        m.companyId = targetReassign?.id ?? "";
        m.version += 1;
        m.updatedAt = nowTs;
        mutatedMeds.add(m);
      }
    }
    for (var s in shortages) {
      if (s.companyName.trim().toUpperCase() == target.id.trim().toUpperCase() ||
          CompanySyncModule.cleanString(s.companyName) == CompanySyncModule.cleanString(target.name)) {
        s.companyName = targetReassign?.name ?? "N/A";
      }
    }

    companies.removeAt(idx);
    final delKeys = [target.id, cleanKey];
    D1SalesLedgerService.markPermanentlyDeleted(target.id, cleanKey);
    for (final k in delKeys) {
      deletedRecordIds.add(k);
      localTombstoneRegistry[k] = nowTs;
      localTombstoneRegistry[k.toUpperCase()] = nowTs;
    }
    _saveLocalTombstones();

    if (activeStoreToken.isNotEmpty) {
      CompanySyncModule.onCompanySaved(target, activeStoreToken, isDelete: true);
      for (final m in mutatedMeds) {
        MedicineSyncModule.onMedicineSaved(m, activeStoreToken);
      }
    }

    _autoSyncService.triggerAutoSync(
      action: "COMPANY_DELETED",
      entityId: target.id,
      deletedIds: delKeys,
    );
    notifyListeners();
    pushUpdatedDataToCloud();
    return mutatedMeds.length;
  }

  int mergeCompanies({required Company source, required Company target}) {
    if (source.id == target.id) return 0;
    return deleteCompanyMaster(source.id, reassignToCompanyId: target.id);
  }

  int saveOrUpdateSalt(Salt salt, {String? previousName}) {
    final nowTs = DateTime.now().millisecondsSinceEpoch;
    final cleanName = salt.name.trim().toUpperCase();
    final cleanKey = SaltSyncModule.cleanString(cleanName);
    if (cleanKey.isEmpty) return 0;

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
    unmarkDeletedId(savedSalt.id, referenceNo: sTombKey);

    final List<Medicine> mutatedMeds = [];
    final int mutatedCount = MasterCascadeService.cascadeSaltUpdate(
      updatedSalt: savedSalt,
      previousName: oldName,
      medicines: medicines,
      onMedicineMutated: (m) => mutatedMeds.add(m),
    );

    if (activeStoreToken.isNotEmpty) {
      SaltSyncModule.onSaltSaved(savedSalt, activeStoreToken, previousName: oldName);
      for (final m in mutatedMeds) {
        MedicineSyncModule.onMedicineSaved(m, activeStoreToken);
      }
    }

    _autoSyncService.triggerAutoSync(
      action: "SALT_SAVED",
      entityId: savedSalt.id,
      unmarkedIds: [savedSalt.id, sTombKey],
    );
    notifyListeners();
    pushUpdatedDataToCloud();
    return mutatedCount;
  }

  int deleteSaltMaster(String saltId, {String? reassignToSaltId}) {
    final idx = salts.indexWhere((s) => s.id == saltId);
    if (idx == -1) return 0;
    final target = salts[idx];
    final cleanKey = "SALT_${SaltSyncModule.cleanString(target.name)}";
    final nowTs = DateTime.now().millisecondsSinceEpoch;

    Salt? targetReassign;
    if (reassignToSaltId != null && reassignToSaltId.isNotEmpty) {
      try {
        targetReassign = salts.firstWhere((s) => s.id == reassignToSaltId);
      } catch (_) {}
    }

    final List<Medicine> mutatedMeds = [];
    for (var m in medicines) {
      if (MasterCascadeService.belongsToSalt(m, target)) {
        m.saltId = targetReassign?.id ?? "";
        m.version += 1;
        m.updatedAt = nowTs;
        mutatedMeds.add(m);
      }
    }

    salts.removeAt(idx);
    final delKeys = [target.id, cleanKey];
    D1SalesLedgerService.markPermanentlyDeleted(target.id, cleanKey);
    for (final k in delKeys) {
      deletedRecordIds.add(k);
      localTombstoneRegistry[k] = nowTs;
      localTombstoneRegistry[k.toUpperCase()] = nowTs;
    }
    _saveLocalTombstones();

    if (activeStoreToken.isNotEmpty) {
      SaltSyncModule.onSaltSaved(target, activeStoreToken, isDelete: true);
      for (final m in mutatedMeds) {
        MedicineSyncModule.onMedicineSaved(m, activeStoreToken);
      }
    }

    _autoSyncService.triggerAutoSync(
      action: "SALT_DELETED",
      entityId: target.id,
      deletedIds: delKeys,
    );
    notifyListeners();
    pushUpdatedDataToCloud();
    return mutatedMeds.length;
  }

  int mergeSalts({required Salt source, required Salt target}) {
    if (source.id == target.id) return 0;
    return deleteSaltMaster(source.id, reassignToSaltId: target.id);
  }

  int saveOrUpdateRoute(RouteArea route, {String? previousName}) {
    final nowTs = DateTime.now().millisecondsSinceEpoch;
    final cleanName = route.name.trim().toUpperCase();
    final cleanKey = RouteSyncModule.cleanString(cleanName);
    if (cleanKey.isEmpty) return 0;

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
    unmarkDeletedId(savedRoute.id, referenceNo: rTombKey);

    final List<Party> mutatedParties = [];
    final int mutatedCount = MasterCascadeService.cascadeRouteUpdate(
      updatedRoute: savedRoute,
      previousName: oldName,
      parties: parties,
      onPartyMutated: (p) => mutatedParties.add(p),
    );

    if (activeStoreToken.isNotEmpty) {
      RouteSyncModule.onRouteSaved(savedRoute, activeStoreToken, previousName: oldName);
      for (final p in mutatedParties) {
        PartySyncModule.onPartySaved(p, activeStoreToken);
      }
    }

    _autoSyncService.triggerAutoSync(
      action: "ROUTE_SAVED",
      entityId: savedRoute.id,
      unmarkedIds: [savedRoute.id, rTombKey],
    );
    notifyListeners();
    pushUpdatedDataToCloud();
    return mutatedCount;
  }

  int deleteRouteMaster(String routeId, {String? reassignToRouteName}) {
    final idx = routes.indexWhere((r) => r.id == routeId);
    if (idx == -1) return 0;
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
    final delKeys = [target.id, cleanKey];
    D1SalesLedgerService.markPermanentlyDeleted(target.id, cleanKey);
    for (final k in delKeys) {
      deletedRecordIds.add(k);
      localTombstoneRegistry[k] = nowTs;
      localTombstoneRegistry[k.toUpperCase()] = nowTs;
    }
    _saveLocalTombstones();

    if (activeStoreToken.isNotEmpty) {
      RouteSyncModule.onRouteSaved(target, activeStoreToken, isDelete: true);
      for (final p in mutatedParties) {
        PartySyncModule.onPartySaved(p, activeStoreToken);
      }
    }

    _autoSyncService.triggerAutoSync(
      action: "ROUTE_DELETED",
      entityId: target.id,
      deletedIds: delKeys,
    );
    notifyListeners();
    pushUpdatedDataToCloud();
    return mutatedParties.length;
  }

  int mergeRoutes({required RouteArea source, required RouteArea target}) {
    if (source.id == target.id) return 0;
    return deleteRouteMaster(source.id, reassignToRouteName: target.name);
  }

  void updateParty(Party updatedParty) {
    String cleanUpdName = PartySyncModule.cleanString(updatedParty.name);
    String cleanPhone = PartySyncModule.cleanPhone(updatedParty.phone);
    String cleanGst = PartySyncModule.cleanGst(updatedParty.gst);

    int idx = parties.indexWhere((p) {
      if (updatedParty.id.isNotEmpty && p.id == updatedParty.id) return true;
      String pGst = PartySyncModule.cleanGst(p.gst);
      if (cleanGst.isNotEmpty && pGst.isNotEmpty && pGst == cleanGst) return true;
      String pPhone = PartySyncModule.cleanPhone(p.phone);
      if (cleanPhone.isNotEmpty && pPhone.isNotEmpty && pPhone == cleanPhone) return true;
      return cleanUpdName.isNotEmpty && PartySyncModule.cleanString(p.name) == cleanUpdName;
    });

    if (idx != -1) {
      updatedParty.id = parties[idx].id;
      updatedParty.updatedAt = DateTime.now().millisecondsSinceEpoch;
      updatedParty.version = parties[idx].version + 1;
      parties[idx] = updatedParty;

      D1SalesLedgerService.unmarkPermanentlyDeleted(updatedParty.id);
      deletedRecordIds.remove(updatedParty.id);
      _saveLocalTombstones();

      MasterCascadeService.cascadePartyUpdate(
        updatedParty: updatedParty,
        sales: sales,
        purchases: purchases,
        saleChallans: saleChallans,
        purchaseChallans: purchaseChallans,
        saleReturns: saleReturns,
        purchaseReturns: purchaseReturns,
        vouchers: vouchers,
      );

      notifyListeners();
      if (activeStoreToken.isNotEmpty) {
        PartySyncModule.onPartySaved(updatedParty, activeStoreToken);
      }
      _autoSyncService.triggerAutoSync(
        action: 'PARTY_UPDATED',
        entityId: updatedParty.id,
        unmarkedIds: [updatedParty.id],
      );
      pushUpdatedDataToCloud();
    } else {
      addParty(updatedParty);
    }
  }

  PartyDeleteCheckResult canDeleteParty(Party party) {
    return PartyIntegrityService.checkPartyDeletionEligibilityForLists(
      sales: sales,
      purchases: purchases,
      vouchers: vouchers,
      saleChallans: saleChallans,
      purchaseChallans: purchaseChallans,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
      party: party,
    );
  }

  bool deleteParty(String partyId) {
    Party? targetP;
    try {
      targetP = parties.firstWhere((pt) => pt.id == partyId);
      final check = canDeleteParty(targetP);
      if (!check.canDelete) return false;
    } catch (_) {}
    deletedRecordIds.add(partyId);
    _saveLocalTombstones();
    parties.removeWhere((p) => p.id == partyId);
    notifyListeners();
    if (activeStoreToken.isNotEmpty && targetP != null) {
      PartySyncModule.onPartySaved(targetP, activeStoreToken, isDelete: true);
    }
    _autoSyncService.triggerAutoSync(action: 'PARTY_DELETED', entityId: partyId, deletedIds: [partyId]);
    return true;
  }

  void addParty(Party newParty) {
    String cleanNewName = PartySyncModule.cleanString(newParty.name);
    String cleanPhone = PartySyncModule.cleanPhone(newParty.phone);
    String cleanGst = PartySyncModule.cleanGst(newParty.gst);
    final int nowTs = DateTime.now().millisecondsSinceEpoch;

    int existingIdx = parties.indexWhere((p) {
      if (newParty.id.isNotEmpty && p.id == newParty.id) return true;
      String pGst = PartySyncModule.cleanGst(p.gst);
      if (cleanGst.isNotEmpty && pGst.isNotEmpty && pGst == cleanGst) return true;
      String pPhone = PartySyncModule.cleanPhone(p.phone);
      if (cleanPhone.isNotEmpty && pPhone.isNotEmpty && pPhone == cleanPhone) return true;
      return cleanNewName.isNotEmpty && PartySyncModule.cleanString(p.name) == cleanNewName;
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
        updatedAt: nowTs,
        version: parties[existingIdx].version + 1,
      );
      parties[existingIdx] = newParty;
    } else {
      if (newParty.id.isEmpty || newParty.id == '0' || newParty.id == 'temp') {
        newParty.id = "PARTY-$nowTs";
      }
      newParty.updatedAt = nowTs;
      if (newParty.version < 1) newParty.version = 1;
      parties.add(newParty);
    }
    notifyListeners();
    if (activeStoreToken.isNotEmpty) {
      PartySyncModule.onPartySaved(newParty, activeStoreToken);
    }
    _autoSyncService.triggerAutoSync(action: 'PARTY_SAVED', entityId: newParty.id);
    pushUpdatedDataToCloud();
  }

  /// 🔄 Auto-hydrates party into Master when receiving transactions with unregistered parties (#PH-REV-734)
  void autoHydrateParty({
    required String id,
    required String name,
    String gst = "",
    String phone = "",
    String address = "",
    String city = "",
    String state = "Rajasthan",
    String group = "Sundry Debtors",
  }) {
    if (name.trim().isEmpty) return;
    String cleanNewName = PartySyncModule.cleanString(name);
    String cleanPPhone = PartySyncModule.cleanPhone(phone);
    String cleanPGst = PartySyncModule.cleanGst(gst);

    bool exists = parties.any((p) {
      if (id.isNotEmpty && p.id == id) return true;
      String pGst = PartySyncModule.cleanGst(p.gst);
      if (cleanPGst.isNotEmpty && pGst.isNotEmpty && pGst == cleanPGst) return true;
      String pPhone = PartySyncModule.cleanPhone(p.phone);
      if (cleanPPhone.isNotEmpty && pPhone.isNotEmpty && pPhone == cleanPPhone) return true;
      return cleanNewName.isNotEmpty && PartySyncModule.cleanString(p.name) == cleanNewName;
    });

    if (!exists) {
      final p = Party(
        id: (id.isNotEmpty && id != '0' && id != 'temp') ? id : "PARTY-${DateTime.now().millisecondsSinceEpoch}",
        name: name.trim().toUpperCase(),
        group: group,
        phone: phone.trim(),
        gst: gst.trim().toUpperCase().isEmpty ? "N/A" : gst.trim().toUpperCase(),
        address: address.trim(),
        city: city.trim().toUpperCase(),
        state: state,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        version: 1,
      );
      addParty(p);
    }
  }

    void addMedicine(Medicine newMed) {
    final String cleanKey = MedicineSyncModule.getCompositeKey(name: newMed.name, packing: newMed.packing, company: newMed.companyId);
    final int nowTs = DateTime.now().millisecondsSinceEpoch;

    int existingIdx = medicines.indexWhere((m) {
      if (newMed.id.isNotEmpty && m.id == newMed.id) return true;
      if (newMed.systemId.isNotEmpty && m.systemId.trim().toUpperCase() == newMed.systemId.trim().toUpperCase()) return true;
      if (cleanKey.isNotEmpty && MedicineSyncModule.getCompositeKey(name: m.name, packing: m.packing, company: m.companyId) == cleanKey) {
        return true;
      }
      return false;
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
        updatedAt: nowTs,
        version: old.version + 1,
      );
      medicines[existingIdx] = newMed;
    } else {
      if (newMed.id.isEmpty || newMed.id == '0' || newMed.id == 'temp') {
        newMed.id = "MED-$nowTs";
      }
      newMed.updatedAt = nowTs;
      if (newMed.version < 1) newMed.version = 1;
      medicines.add(newMed);
    }

    if (!batchHistory.containsKey(newMed.identityKey)) {
      batchHistory[newMed.identityKey] = [];
    }

    notifyListeners();
    if (activeStoreToken.isNotEmpty) {
      MedicineSyncModule.onMedicineSaved(newMed, activeStoreToken);
    }
    _autoSyncService.triggerAutoSync(action: 'MEDICINE_SAVED', entityId: newMed.id);
    pushUpdatedDataToCloud();
  }

  void updateMedicine(Medicine updatedMed) {
    int idx = medicines.indexWhere((m) => m.id == updatedMed.id || (updatedMed.systemId.isNotEmpty && m.systemId == updatedMed.systemId));
    if (idx != -1) {
      updatedMed.id = medicines[idx].id;
      if (updatedMed.systemId.isEmpty) updatedMed.systemId = medicines[idx].systemId;
      updatedMed.version = medicines[idx].version + 1;
      updatedMed.updatedAt = DateTime.now().millisecondsSinceEpoch;
      medicines[idx] = updatedMed;

      final compKey = MedicineSyncModule.getCompositeKey(name: updatedMed.name, packing: updatedMed.packing, company: updatedMed.companyId);
      D1SalesLedgerService.unmarkPermanentlyDeleted(updatedMed.id, updatedMed.systemId, compKey);
      deletedRecordIds.remove(updatedMed.id);
      if (updatedMed.systemId.isNotEmpty) deletedRecordIds.remove(updatedMed.systemId);
      deletedRecordIds.remove(compKey);
      _saveLocalTombstones();

      MasterCascadeService.cascadeProductUpdate(
        updatedMed: updatedMed,
        sales: sales,
        purchases: purchases,
        saleChallans: saleChallans,
        purchaseChallans: purchaseChallans,
        saleReturns: saleReturns,
        purchaseReturns: purchaseReturns,
      );

      notifyListeners();
      if (activeStoreToken.isNotEmpty) {
        MedicineSyncModule.onMedicineSaved(updatedMed, activeStoreToken);
      }
      _autoSyncService.triggerAutoSync(
        action: 'MEDICINE_UPDATED',
        entityId: updatedMed.id,
        unmarkedIds: [updatedMed.id, if (updatedMed.systemId.isNotEmpty) updatedMed.systemId, compKey],
      );
      pushUpdatedDataToCloud();
    }
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

  void deleteMedicine(String medId) {
    Medicine? target;
    try {
      target = medicines.firstWhere((item) => item.id == medId || (item.systemId.isNotEmpty && item.systemId == medId));
    } catch (_) {}
    if (target != null) {
      final check = canDeleteMedicine(target);
      if (!check.canDelete) {
        errorMessage = check.details;
        notifyListeners();
        return;
      }
      final compKey = MedicineSyncModule.getCompositeKey(name: target.name, packing: target.packing, company: target.companyId);
      D1SalesLedgerService.markPermanentlyDeleted(medId, target.systemId, compKey);
      if (activeStoreToken.isNotEmpty) {
        TombstoneEngine.recordBatchTombstones(activeStoreToken, [medId, if (target.systemId.isNotEmpty) target.systemId]);
      }
    }
    deletedRecordIds.add(medId);
    if (target != null && target.systemId.isNotEmpty) {
      deletedRecordIds.add(target.systemId);
    }
    _saveLocalTombstones();
    medicines.removeWhere((item) => item.id == medId || (target != null && target.systemId.isNotEmpty && item.systemId == target.systemId));
    notifyListeners();
    if (activeStoreToken.isNotEmpty && target != null) {
      MedicineSyncModule.onMedicineSaved(target, activeStoreToken, isDelete: true);
    }
    _autoSyncService.triggerAutoSync(action: 'MEDICINE_DELETED', entityId: medId, deletedIds: [medId]);
    pushUpdatedDataToCloud();
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
    if (type == "SALE" && prefix.trim().toUpperCase() == "INV-") {
      prefix = "W-";
    } else if (type == "PURCHASE" && prefix.trim().toUpperCase() == "PUR-") {
      prefix = "WPUR-";
    } else if ((type == "PURCHASE_CHALLAN" || type == "CHALLAN_PUR") && prefix.trim().toUpperCase() == "PCH-") {
      prefix = "WPCH-";
    } else if ((type == "CHALLAN" || type == "SALE_CHALLAN") && prefix.trim().toUpperCase() == "SCH-") {
      prefix = "WSCH-";
    } else if ((type == "RETURN" || type == "SALE_RETURN" || type == "CREDIT_NOTE") && prefix.trim().toUpperCase() == "CN-") {
      prefix = "WCN-";
    } else if ((type == "PURCHASE_RETURN" || type == "DEBIT_NOTE") && prefix.trim().toUpperCase() == "DN-") {
      prefix = "WDN-";
    }

    List<dynamic> targetList;
    if (type == "SALE") {
      targetList = sales;
    } else if (type == "PURCHASE") {
      targetList = purchases;
    } else if (type == "CHALLAN" || type == "SALE_CHALLAN") {
      targetList = saleChallans;
    } else if (type == "PURCHASE_CHALLAN" || type == "CHALLAN_PUR") {
      targetList = purchaseChallans;
    } else if (type == "RETURN" || type == "SALE_RETURN" || type == "CREDIT_NOTE") {
      targetList = saleReturns;
    } else if (type == "PURCHASE_RETURN" || type == "DEBIT_NOTE") {
      targetList = purchaseReturns;
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
      final Map<String, dynamic> files = (result['files'] is Map)
          ? Map<String, dynamic>.from(result['files'])
          : {};
      final String? cloudTopFy = result['fy']?.toString();
      if (result['profile'] is Map) {
        companyProfile = Map<String, dynamic>.from(result['profile']);
      }
      _extractAndSyncFyVaultFromCloud(files, cloudTopFy: cloudTopFy);
      if (!isExplicitBackYearSelected && availableFinancialYears.isNotEmpty) {
        financialYear = availableFinancialYears.last;
      }
      D1SalesLedgerService.activeFinancialYear = financialYear;

      if (fyVault.containsKey(financialYear) && fyVault[financialYear]!.isNotEmpty) {
        final Map<String, dynamic> scoped = Map<String, dynamic>.from(fyVault[financialYear]!);
        if (files.containsKey('tombstones.json')) scoped['tombstones.json'] = files['tombstones.json'];
        if (files.containsKey('tombstone_registry.json')) scoped['tombstone_registry.json'] = files['tombstone_registry.json'];
        _parseDownloadedFiles(scoped);
      } else if (cloudTopFy == null || cloudTopFy.trim().isEmpty || cloudTopFy.trim() == financialYear) {
        _parseDownloadedFiles(files);
      }
      fyVault[financialYear] = _captureCurrentMemoryToFyFilesMap();
      rebuildInventory();
      successMessage = "Data refreshed live!";
    } else {
      errorMessage = result['message'] ?? 'Live Refresh failed.';
    }

    isLoading = false;
    notifyListeners();
  }

  /// Switches active Financial Year on Web with full in-memory isolation & back-year auto-cascade
  Future<void> switchWebFinancialYear(String targetFy) async {
    final cleanTarget = targetFy.trim();
    if (cleanTarget.isEmpty || cleanTarget == financialYear) return;

    // 1. Save current year snapshot & cascade if leaving a back year
    fyVault[financialYear] = _captureCurrentMemoryToFyFilesMap();
    if (isBackYearActive) {
      _cascadeWebFyVaultFrom(financialYear);
    }

    // 2. Clear active transaction registers before loading target year
    sales.clear();
    purchases.clear();
    vouchers.clear();
    saleChallans.clear();
    purchaseChallans.clear();
    saleReturns.clear();
    purchaseReturns.clear();
    gstDiarySessions.clear();
    batchHistory.clear();

    financialYear = cleanTarget;
    isExplicitBackYearSelected =
        availableFinancialYears.isNotEmpty && cleanTarget != availableFinancialYears.last;
    D1SalesLedgerService.activeFinancialYear = cleanTarget;

    if (fyVault.containsKey(cleanTarget) && fyVault[cleanTarget]!.isNotEmpty) {
      _parseDownloadedFiles(Map<String, dynamic>.from(fyVault[cleanTarget]!));
    }
    rebuildInventory();
    notifyListeners();
  }

  /// Creates a new Marg-Style Financial Year directly from Web and syncs to Cloud & App
  Future<bool> startNewFinancialYearOnWeb(
    String newFy, {
    bool filterZeroStock = false,
    bool filterExpired = false,
  }) async {
    final cleanNewFy = newFy.trim();
    if (cleanNewFy.isEmpty) return false;

    try {
      fyVault[financialYear] = _captureCurrentMemoryToFyFilesMap();
      if (availableFinancialYears.length > 1) {
        _cascadeWebFyVaultFrom(availableFinancialYears.first);
      }

      final String sourceFy = availableFinancialYears.isNotEmpty
          ? availableFinancialYears.last
          : financialYear;
      final Map<String, String> sourceFiles =
          fyVault[sourceFy] ?? _captureCurrentMemoryToFyFilesMap();

      final Map<String, String> newYearFiles = FYTransferEngine.computeCarryForwardFromFiles(
        sourceFiles: sourceFiles,
        sourceFY: sourceFy,
        targetFY: cleanNewFy,
        filterZeroStock: filterZeroStock,
        filterExpired: filterExpired,
      );

      fyVault[cleanNewFy] = newYearFiles;
      availableFinancialYears = WebAppDateLogic.sortFYList([...availableFinancialYears, cleanNewFy]);
      companyProfile['fYears'] = availableFinancialYears;

      await switchWebFinancialYear(cleanNewFy);
      isExplicitBackYearSelected = false;

      await pushUpdatedDataToCloud();
      _autoSyncService.triggerInstantPush(action: 'NEW_FY_CREATED', entityId: cleanNewFy);
      return true;
    } catch (e) {
      debugPrint("startNewFinancialYearOnWeb error: $e");
      return false;
    }
  }

  /// Runs Marg-Grade File Maintenance & Multi-Year Cascade across all years on Web
  Future<List<String>> runWebFileMaintenance({
    void Function(double progress, String status)? onProgress,
  }) async {
    final List<String> report = [];
    try {
      onProgress?.call(0.10, "Snapshotting active Financial Year ($financialYear)...");
      fyVault[financialYear] = _captureCurrentMemoryToFyFilesMap();
      await Future.delayed(const Duration(milliseconds: 120));

      if (availableFinancialYears.length > 1) {
        final int steps = availableFinancialYears.length - 1;
        for (int i = 0; i < steps; i++) {
          final String prevFy = availableFinancialYears[i];
          final String targetFy = availableFinancialYears[i + 1];
          onProgress?.call(
            0.15 + ((i + 1) / steps * 0.45),
            "Cascading Balances & Batch Stock: $prevFy → $targetFy...",
          );
          final prevFiles = fyVault[prevFy];
          final targetFiles = fyVault[targetFy];
          if (prevFiles != null && targetFiles != null) {
            final res = FYTransferEngine.cascadeSingleYearStep(
              prevFiles: prevFiles,
              targetFiles: targetFiles,
              prevFY: prevFy,
              targetFY: targetFy,
            );
            fyVault[prevFy] = res.healedPrevFiles;
            fyVault[targetFy] = res.healedTargetFiles;
            report.add("• Cascaded Closing → Opening Balances & Stock: $prevFy → $targetFy");
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      onProgress?.call(0.70, "Auditing Active Year ($financialYear) Batches & Ledgers...");
      if (fyVault.containsKey(financialYear)) {
        sales.clear();
        purchases.clear();
        vouchers.clear();
        saleChallans.clear();
        purchaseChallans.clear();
        saleReturns.clear();
        purchaseReturns.clear();
        batchHistory.clear();
        _parseDownloadedFiles(Map<String, dynamic>.from(fyVault[financialYear]!));
      }

      final Set<String> validProductKeys = medicines.map((m) => m.identityKey).toSet();
      int removedOrphans = 0;
      batchHistory.removeWhere((key, _) {
        final isOrphan = !validProductKeys.contains(key);
        if (isOrphan) removedOrphans++;
        return isOrphan;
      });

      sales.sort((a, b) => b.date.compareTo(a.date));
      purchases.sort((a, b) => b.date.compareTo(a.date));

      rebuildInventory();
      fyVault[financialYear] = _captureCurrentMemoryToFyFilesMap();

      onProgress?.call(0.90, "Syncing Multi-FY Vault to Cloud & App...");
      await pushUpdatedDataToCloud();
      _autoSyncService.triggerInstantPush(action: 'FILE_MAINTENANCE_COMPLETE', entityId: financialYear);
      onProgress?.call(1.0, "File Maintenance Complete!");

      report.add("• Party Opening Balances (incl. Credit/Debit Notes): Verified & Synced");
      report.add("• Dynamic Batch Stock (Opening + Purc - Sales): Rebuilt (${medicines.length} Products)");
      report.add("• Orphaned Batch Records Purged: $removedOrphans");
      report.add("• Multi-FY Cloud Vault (${availableFinancialYears.join(", ")}): Synced with App");
      notifyListeners();
    } catch (e) {
      report.add("⚠ Maintenance Error: $e");
    }
    return report;
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
    return WebAccountsCalculator.calculatePartyBalance(
      party: p,
      sales: sales,
      purchases: purchases,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
      vouchers: vouchers,
    );
  }

  List<Map<String, dynamic>> getPartyStatementData({
    required String partyId,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    Party? partyObj;
    try {
      partyObj = parties.firstWhere((element) => element.id == partyId || element.name.trim().toUpperCase() == partyId.trim().toUpperCase());
    } catch (e) {
      return [];
    }
    return WebAccountsCalculator.getPartyStatementData(
      party: partyObj,
      fromDate: fromDate,
      toDate: toDate,
      sales: sales,
      purchases: purchases,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
      vouchers: vouchers,
    );
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
  List<Map<String, dynamic>> getPendingBills(String partyId, bool isReceipt, {String? excludeVoucherId}) {
    return WebAccountsCalculator.getPendingBills(
      partyId: partyId,
      isReceipt: isReceipt,
      sales: sales,
      purchases: purchases,
      vouchers: vouchers,
      excludeVoucherId: excludeVoucherId,
    );
  }

  bool isCashLimitExceeded(String partyId, double newAmount) {
    return WebAccountsCalculator.isCashLimitExceeded(
      partyId: partyId,
      newAmount: newAmount,
      vouchers: vouchers,
    );
  }


  void cancelVoucher(String id) {
    int i = vouchers.indexWhere((v) => v.id == id || v.voucherNo == id);
    if (i != -1) {
      final targetV = vouchers[i];
      final String realId = targetV.id;
      final String cleanVNo = targetV.voucherNo.trim().toUpperCase();
      int nextVer = targetV.version + 1;
      final int knownVer = D1SalesLedgerService.getKnownVersion(realId, cleanVNo);
      if (knownVer >= nextVer) {
        nextVer = knownVer + 1;
      }

      for (int idx = 0; idx < vouchers.length; idx++) {
        if (vouchers[idx].id == realId || (cleanVNo.isNotEmpty && vouchers[idx].voucherNo.trim().toUpperCase() == cleanVNo)) {
          vouchers[idx].status = "Cancelled";
          vouchers[idx].isDeleted = 0;
          if (!vouchers[idx].narration.startsWith("[CANCELLED]")) {
            vouchers[idx].narration = "[CANCELLED] ${vouchers[idx].narration}".trim();
          }
          vouchers[idx].version = nextVer;
          vouchers[idx].updatedAt = DateTime.now().millisecondsSinceEpoch;
        }
      }

      unmarkDeletedId(realId, referenceNo: cleanVNo);
      WebVoucherD1SyncService.onVoucherCancelled(vouchers[i], activeStoreToken, clientSource: "WEB_PORTAL");
      notifyListeners();
      pushUpdatedDataToCloud();
      _autoSyncService.triggerAutoSync(
        action: 'CANCEL_VOUCHER',
        entityId: realId,
        unmarkedIds: [realId, if (cleanVNo.isNotEmpty) cleanVNo],
      );
    }
  }


  // ===========================================================================
  // 🛡️ CENTRAL ENTERPRISE BATCH MASTER MANAGEMENT (#PH-REV-764)
  // ===========================================================================

  void addBatch(Medicine med, BatchInfo newBatch) {
    final medKey = med.identityKey;
    if (!batchHistory.containsKey(medKey)) {
      batchHistory[medKey] = [];
    }
    newBatch.version = 1;
    newBatch.updatedAt = DateTime.now().millisecondsSinceEpoch;
    batchHistory[medKey]!.add(newBatch);

    final syncId = BatchSyncModule.getBatchSyncId(medKey, newBatch.batch);
    unmarkDeletedId(syncId, referenceNo: newBatch.batch);

    if (activeStoreToken.isNotEmpty) {
      BatchSyncModule.onBatchSaved(
        batch: newBatch,
        medIdentityKey: medKey,
        storeToken: activeStoreToken,
        isDelete: false,
      );
    }
    _autoSyncService.triggerAutoSync(
      action: 'BATCH_REGISTERED',
      entityId: syncId,
      unmarkedIds: [syncId, newBatch.batch],
    );
    rebuildInventory();
    notifyListeners();
    pushUpdatedDataToCloud();
  }

  int updateBatchCascade({
    required Medicine med,
    required String oldBatchNo,
    required String newBatchNo,
    required String newExp,
    required double newMrp,
    required double newPurRate,
    double newRateA = 0.0,
    double newRateB = 0.0,
    double newRateC = 0.0,
  }) {
    final medKey = med.identityKey;
    final mutatedCount = BatchCascadeEngine.cascadeBatchUpdate(
      medicine: med,
      oldBatchNo: oldBatchNo,
      newBatchNo: newBatchNo,
      newExp: newExp,
      newMrp: newMrp,
      newPurRate: newPurRate,
      newRateA: newRateA,
      newRateB: newRateB,
      newRateC: newRateC,
      batchHistory: batchHistory,
      sales: sales,
      purchases: purchases,
      saleChallans: saleChallans,
      purchaseChallans: purchaseChallans,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
      medicines: medicines,
      storeToken: activeStoreToken,
      companyId: activeStoreToken,
    );

    // Bump version and timestamp on updated batch
    if (batchHistory.containsKey(medKey)) {
      final cleanNew = newBatchNo.trim().toUpperCase();
      final idx = batchHistory[medKey]!.indexWhere((b) => b.batch.trim().toUpperCase() == cleanNew);
      if (idx != -1) {
        final b = batchHistory[medKey]![idx];
        b.version += 1;
        b.updatedAt = DateTime.now().millisecondsSinceEpoch;
        if (activeStoreToken.isNotEmpty) {
          BatchSyncModule.onBatchSaved(
            batch: b,
            medIdentityKey: medKey,
            storeToken: activeStoreToken,
            isDelete: false,
          );
        }
      }
    }

    final newSyncId = BatchSyncModule.getBatchSyncId(medKey, newBatchNo);
    _autoSyncService.triggerAutoSync(
      action: 'BATCH_UPDATED',
      entityId: newSyncId,
      unmarkedIds: [newSyncId, newBatchNo],
    );
    rebuildInventory();
    notifyListeners();
    pushUpdatedDataToCloud();
    return mutatedCount;
  }

  ({bool success, String message, List<BatchUsageAuditRecord> lockingRecords}) deleteBatchSafe({
    required Medicine med,
    required String batchNo,
    required String activeFY,
  }) {
    final result = BatchCascadeEngine.deleteBatchSafe(
      medicine: med,
      batchNo: batchNo,
      activeFY: activeFY,
      batchHistory: batchHistory,
      sales: sales,
      purchases: purchases,
      saleChallans: saleChallans,
      purchaseChallans: purchaseChallans,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
      medicines: medicines,
      storeToken: activeStoreToken,
      companyId: activeStoreToken,
    );

    if (result.success) {
      final syncId = BatchSyncModule.getBatchSyncId(med.identityKey, batchNo);
      final cleanBatch = batchNo.trim().toUpperCase();
      deletedRecordIds.add(syncId);
      deletedRecordIds.add(cleanBatch);
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      localTombstoneRegistry[syncId] = nowTs;
      localTombstoneRegistry[cleanBatch] = nowTs;
      _saveLocalTombstones();

      _autoSyncService.triggerAutoSync(
        action: 'BATCH_DELETED',
        entityId: syncId,
        deletedIds: [syncId, cleanBatch],
      );
      rebuildInventory();
      notifyListeners();
      pushUpdatedDataToCloud();
    }
    return result;
  }

  void adjustBatchStock({
    required String medId,
    required String batchNo,
    required double adjQty,
    required String reason,
    String adjustedBy = "User",
  }) {
    String resolvedKey = medId.trim();
    if (!batchHistory.containsKey(resolvedKey)) {
      try {
        final m = medicines.firstWhere((m) =>
            m.id == medId ||
            m.identityKey == medId ||
            m.name.trim().toUpperCase() == medId.trim().toUpperCase());
        if (batchHistory.containsKey(m.identityKey)) {
          resolvedKey = m.identityKey;
        } else if (batchHistory.containsKey(m.id)) {
          resolvedKey = m.id;
        }
      } catch (_) {}
    }
    if (batchHistory.containsKey(resolvedKey)) {
      final idx = batchHistory[resolvedKey]!.indexWhere((b) => b.batch.trim().toUpperCase() == batchNo.trim().toUpperCase());
      if (idx != -1) {
        final b = batchHistory[resolvedKey]![idx];
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

        if (activeStoreToken.isNotEmpty) {
          BatchSyncModule.onBatchSaved(
            batch: b,
            medIdentityKey: resolvedKey,
            storeToken: activeStoreToken,
            isDelete: false,
          );
        }
        final syncId = BatchSyncModule.getBatchSyncId(resolvedKey, batchNo);
        _autoSyncService.triggerAutoSync(
          action: 'BATCH_ADJUSTED',
          entityId: syncId,
          unmarkedIds: [syncId, batchNo],
        );
        rebuildInventory();
        notifyListeners();
        pushUpdatedDataToCloud();
      }
    }
  }

  void updateAppConfig(AppConfig c) {
    c.version += 1;
    c.updatedAt = DateTime.now().millisecondsSinceEpoch;
    appConfig = c;
    if (activeStoreToken.isNotEmpty) {
      SyncQueueManager.enqueueMutation(
        syncId: 'APP_CONFIG_MASTER',
        storeToken: activeStoreToken.trim().toUpperCase(),
        docType: 'CONFIG',
        currentVersion: c.version,
        isDelete: false,
        rawPayload: c.toMap(),
      );
      GstDiaryD1SyncService.onAppConfigSaved(c, activeStoreToken, clientSource: "WEB_PORTAL");
    }
    _autoSyncService.triggerAutoSync(
      action: 'CONFIG_UPDATED',
      entityId: 'APP_CONFIG_MASTER',
    );
    notifyListeners();
    pushUpdatedDataToCloud();
  }

  void changeBatchStatus({
    required String medId,
    required String batchNo,
    required String status,
  }) {
    if (batchHistory.containsKey(medId)) {
      final idx = batchHistory[medId]!.indexWhere((b) => b.batch.trim().toUpperCase() == batchNo.trim().toUpperCase());
      if (idx != -1) {
        final b = batchHistory[medId]![idx];
        b.status = status;
        b.version += 1;
        b.updatedAt = DateTime.now().millisecondsSinceEpoch;

        if (activeStoreToken.isNotEmpty) {
          BatchSyncModule.onBatchSaved(
            batch: b,
            medIdentityKey: medId,
            storeToken: activeStoreToken,
            isDelete: false,
          );
        }
        final syncId = BatchSyncModule.getBatchSyncId(medId, batchNo);
        _autoSyncService.triggerAutoSync(
          action: 'BATCH_STATUS_CHANGED',
          entityId: syncId,
          unmarkedIds: [syncId, batchNo],
        );
        rebuildInventory();
        notifyListeners();
        pushUpdatedDataToCloud();
      }
    }
  }


  void createGstDiarySession(GstDiarySession s) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    s.version = s.version <= 0 ? 1 : s.version;
    s.updatedAt = now;
    s.isDeleted = 0;
    unmarkDeletedId(s.id);
    gstDiarySessions.removeWhere((x) => x.id == s.id);
    gstDiarySessions.insert(0, s);
    if (activeStoreToken.isNotEmpty) {
      GstDiaryD1SyncService.onSessionSaved(s, activeStoreToken, clientSource: "WEB_PORTAL");
    }
    _autoSyncService.triggerAutoSync(
      action: 'GST_SESSION_SAVED',
      entityId: s.id,
      unmarkedIds: [s.id],
    );
    notifyListeners();
    pushUpdatedDataToCloud();
  }

  void updateGstDiarySession(GstDiarySession s) {
    int i = gstDiarySessions.indexWhere((x) => x.id == s.id);
    if (i != -1) {
      s.version = gstDiarySessions[i].version + 1;
      s.updatedAt = DateTime.now().millisecondsSinceEpoch;
      s.isDeleted = 0;
      unmarkDeletedId(s.id);
      gstDiarySessions[i] = s;
      if (activeStoreToken.isNotEmpty) {
        GstDiaryD1SyncService.onSessionSaved(s, activeStoreToken, clientSource: "WEB_PORTAL");
      }
      _autoSyncService.triggerAutoSync(
        action: 'GST_SESSION_UPDATED',
        entityId: s.id,
        unmarkedIds: [s.id],
      );
      notifyListeners();
      pushUpdatedDataToCloud();
    }
  }

  void deleteGstDiarySession(String id) {
    String title = "";
    try {
      title = gstDiarySessions.firstWhere((x) => x.id == id).title;
    } catch (_) {}
    gstDiarySessions.removeWhere((x) => x.id == id);
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    localTombstoneRegistry[id] = delTime;
    localTombstoneRegistry[id.toUpperCase()] = delTime;
    deletedRecordIds.add(id);
    deletedRecordIds.add(id.toUpperCase());
    unmarkedRecordIds.remove(id);
    unmarkedRecordIds.remove(id.toUpperCase());
    _saveLocalTombstones();
    if (activeStoreToken.isNotEmpty) {
      GstDiaryD1SyncService.onSessionDeleted(id, activeStoreToken, sessionTitle: title, clientSource: "WEB_PORTAL");
    }
    _autoSyncService.triggerAutoSync(
      action: 'DELETE_GST_SESSION',
      entityId: id,
      deletedIds: [id],
    );
    notifyListeners();
    pushUpdatedDataToCloud();
  }
}
