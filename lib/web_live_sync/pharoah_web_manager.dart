import '../sync_core/modules/returns_sync_module.dart';
import "../sync_core/d1_sales_ledger_service.dart";
import '../sync_core/modules/sales_sync_module.dart';
import '../sync_core/modules/purchase_sync_module.dart';
import '../sync_core/modules/sale_challan_sync_module.dart';
import '../sync_core/modules/purchase_challan_sync_module.dart';
import '../sync_core/modules/challan_sync_module.dart';
import '../sync_core/modules/voucher_sync_module.dart';
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
      return set.contains(c.id) || (bNo.isNotEmpty && (set.contains(bNo) || upperSet.contains(bNo)));
    });

    purchaseChallans.removeWhere((c) {
      final iNo = c.internalNo.trim().toUpperCase();
      final bNo = c.billNo.trim().toUpperCase();
      return set.contains(c.id) ||
          (iNo.isNotEmpty && (set.contains(iNo) || upperSet.contains(iNo))) ||
          (bNo.isNotEmpty && (set.contains(bNo) || upperSet.contains(bNo)));
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

  void _populateDataFromCloud(String token, String user, String pass, Map<String, dynamic> result) {
    activeStoreToken = token.trim().toUpperCase();
    activeUsername = user.trim();
    activePassword = pass.trim();
    companyName = result['companyName'] ?? 'STORE WORKSTATION';
    financialYear = (result['fy'] != null && result['fy'].toString().trim().isNotEmpty)
        ? result['fy'].toString().trim()
        : WebAppDateLogic.getCurrentFYString();
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
      String cleanName = p.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
      String cleanKey = p.id.trim().isNotEmpty ? p.id.trim() : cleanName;
      if (cleanKey.isEmpty) continue;
      if (!uniqueParties.containsKey(cleanKey)) {
        uniqueParties[cleanKey] = p;
      } else if (p.updatedAt >= uniqueParties[cleanKey]!.updatedAt) {
        uniqueParties[cleanKey] = p;
      }
    }
    parties = uniqueParties.values.toList();

    // 1. Sales Sync with Anti-Zombie Shield & Strict LWW Guard (MANDATE 1 & 2)
    var allParsedSales = (decodeJson('sales.json') as List?)
        ?.map((e) => Sale.fromMap(e))
        .toList();
    if (allParsedSales != null) {
      for (var s in allParsedSales) {
        if (s.id.isEmpty) continue;

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
        if (deletedRecordIds.contains(s.id) || (cleanBillNo.isNotEmpty && deletedRecordIds.contains(cleanBillNo))) {
          continue; // Blocked by Permanent Tombstone!
        }
        if (localTombstoneRegistry.containsKey(s.id) || (cleanBillNo.isNotEmpty && localTombstoneRegistry.containsKey(cleanBillNo))) {
          continue; // Blocked by Tombstone Registry!
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

      // 🚀 EDGE D1 REAL-TIME SALES DELTAS HARVEST
      if (D1SalesLedgerService.USE_D1_EDGE_LEDGER && activeStoreToken.isNotEmpty) {
        D1SalesLedgerService.fetchSaleDeltas(activeStoreToken).then((edgeEvents) {
          if (edgeEvents.isNotEmpty) {
            if (D1SalesLedgerService.applyEventsToLocalSales(sales, edgeEvents)) {
              // Post-D1 Deduplication pass
              Map<String, Sale> postD1Map = {};
              for (var s in sales) {
                String key = s.billNo.trim().toUpperCase();
                if (key.isEmpty) key = s.id.trim();
                if (!postD1Map.containsKey(key) || s.version >= postD1Map[key]!.version) {
                  postD1Map[key] = s;
                }
              }
              sales = postD1Map.values.toList();
              rebuildInventory();
              notifyListeners();
            }
          }
        }).catchError((_) {});
      }
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

      if (D1SalesLedgerService.USE_D1_EDGE_LEDGER && activeStoreToken.isNotEmpty) {
        D1SalesLedgerService.fetchSaleDeltas(activeStoreToken).then((edgeEvents) {
          if (edgeEvents.isNotEmpty) {
            if (D1SalesLedgerService.applyEventsToLocalPurchases(purchases, edgeEvents)) {
              rebuildInventory();
              notifyListeners();
            }
          }
        }).catchError((_) {});
      }
    }

    // 3. Vouchers Sync with Anti-Zombie Multi-Key Protection
    var allParsedVouc = (decodeJson('vouc.json') as List?)
        ?.map((e) => Voucher.fromMap(e))
        .toList();
    if (allParsedVouc != null) {
      for (var v in allParsedVouc) {
        if (v.isDeleted == 1) continue;
        final String cleanVNo = v.voucherNo.trim().toUpperCase();
        if ((v.id.isNotEmpty && deletedRecordIds.contains(v.id)) ||
            (cleanVNo.isNotEmpty && deletedRecordIds.contains(cleanVNo)) ||
            (v.id.isNotEmpty && localTombstoneRegistry.containsKey(v.id)) ||
            (cleanVNo.isNotEmpty && localTombstoneRegistry.containsKey(cleanVNo))) {
          continue;
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
        if (!masterVoucMap.containsKey(key) || v.version >= masterVoucMap[key]!.version) {
          masterVoucMap[key] = v;
        }
      }
      vouchers = masterVoucMap.values.toList();
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
        if (D1SalesLedgerService.isBillDeleted(c.id, c.billNo)) return false;
        if (c.id.isNotEmpty && (deletedRecordIds.contains(c.id) || deletedRecordIds.contains(c.id.toUpperCase()))) return false;
        int secDelTs = 0;
        if (bNo.isNotEmpty) {
          final t = localTombstoneRegistry[bNo] ?? localTombstoneRegistry[bNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= c.updatedAt) return false;
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
        final String compKey = PurchaseChallanSyncModule.makeCompositeKey(cleanPId, cleanBNo, cleanINo);
        if (c.id.isNotEmpty && (deletedRecordIds.contains(c.id) || deletedRecordIds.contains(c.id.toUpperCase()))) {
          continue; // Blocked by immutable ID tombstone
        }
        int secDelTs = 0;
        if (cleanINo.isNotEmpty) {
          final t = localTombstoneRegistry[cleanINo] ?? localTombstoneRegistry[cleanINo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (cleanBNo.isNotEmpty) {
          final t = localTombstoneRegistry[cleanBNo] ?? localTombstoneRegistry[cleanBNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (compKey.isNotEmpty) {
          final t = localTombstoneRegistry[compKey] ?? localTombstoneRegistry[compKey.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= c.updatedAt) {
          continue; // Blocked by newer or same age series tombstone
        }
        if (cleanINo.isNotEmpty) {
          deletedRecordIds.remove(cleanINo);
          deletedRecordIds.remove(cleanINo.toUpperCase());
        }
        if (cleanBNo.isNotEmpty) {
          deletedRecordIds.remove(cleanBNo);
          deletedRecordIds.remove(cleanBNo.toUpperCase());
        }
        if (compKey.isNotEmpty) {
          deletedRecordIds.remove(compKey);
          deletedRecordIds.remove(compKey.toUpperCase());
        }
        int idx = purchaseChallans.indexWhere((lc) => 
          (c.id.isNotEmpty && lc.id == c.id) ||
          (cleanINo.isNotEmpty && lc.internalNo.trim().toUpperCase() == cleanINo) ||
          (cleanBNo.isNotEmpty && lc.billNo.trim().toUpperCase() == cleanBNo)
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
        final comp = PurchaseChallanSyncModule.makeCompositeKey(pId, bNo, iNo);
        if (D1SalesLedgerService.isPurchaseDeleted(c.id, c.partyId, c.billNo, c.internalNo)) return false;
        if (c.id.isNotEmpty && (deletedRecordIds.contains(c.id) || deletedRecordIds.contains(c.id.toUpperCase()))) return false;
        int secDelTs = 0;
        if (iNo.isNotEmpty) {
          final t = localTombstoneRegistry[iNo] ?? localTombstoneRegistry[iNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (bNo.isNotEmpty) {
          final t = localTombstoneRegistry[bNo] ?? localTombstoneRegistry[bNo.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (comp.isNotEmpty) {
          final t = localTombstoneRegistry[comp] ?? localTombstoneRegistry[comp.toUpperCase()] ?? 0;
          if (t > secDelTs) secDelTs = t;
        }
        if (secDelTs > 0 && secDelTs >= c.updatedAt) return false;
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
        if ((r.id.isNotEmpty && deletedRecordIds.contains(r.id)) ||
            (cleanBNo.isNotEmpty && deletedRecordIds.contains(cleanBNo)) ||
            (r.id.isNotEmpty && localTombstoneRegistry.containsKey(r.id)) ||
            (cleanBNo.isNotEmpty && localTombstoneRegistry.containsKey(cleanBNo))) {
          continue;
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
    }

    // 7. Purchase Returns Sync with Anti-Zombie Multi-Key Protection
    var allParsedPRet = (decodeJson('p_return.json') as List?)
        ?.map((e) => PurchaseReturn.fromMap(e))
        .toList();
    if (allParsedPRet != null) {
      for (var r in allParsedPRet) {
        if (r.isDeleted == 1) continue;
        final String cleanBNo = r.billNo.trim().toUpperCase();
        if ((r.id.isNotEmpty && deletedRecordIds.contains(r.id)) ||
            (cleanBNo.isNotEmpty && deletedRecordIds.contains(cleanBNo)) ||
            (r.id.isNotEmpty && localTombstoneRegistry.containsKey(r.id)) ||
            (cleanBNo.isNotEmpty && localTombstoneRegistry.containsKey(cleanBNo))) {
          continue;
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
    }

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
        'tombstone_registry.json': jsonEncode(localTombstoneRegistry),
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
          }
        }
      }

      SalesSyncModule.onSaleDeleted(s, activeStoreToken);
      D1SalesLedgerService.onSaleDeleted(realId, s.billNo, activeStoreToken, clientSource: "WEB_PORTAL");
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
    if (compKey.isNotEmpty) unmarkDeletedId(compKey);
    if (compKey2.isNotEmpty) unmarkDeletedId(compKey2);
    D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(purchase.id, purchase.partyId, purchase.billNo, purchase.internalNo);

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

  void deleteVoucher(String voucherId) {
    String vNo = "";
    try {
      final targetV = vouchers.firstWhere((item) => item.id == voucherId || item.voucherNo == voucherId);
      vNo = targetV.voucherNo.trim().toUpperCase();
      D1SalesLedgerService.markPermanentlyDeleted(voucherId, vNo);
      VoucherSyncModule.onVoucherDeleted(targetV, activeStoreToken);
    } catch (_) {}
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    final List<String> delKeys = [voucherId, if (vNo.isNotEmpty) vNo];
    for (var k in delKeys) {
      localTombstoneRegistry[k] = delTime;
      deletedRecordIds.add(k);
      unmarkedRecordIds.remove(k);
    }
    _saveLocalTombstones();
    vouchers.removeWhere((item) => item.id == voucherId || (vNo.isNotEmpty && item.voucherNo.trim().toUpperCase() == vNo));
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'RECORD_DELETED',
      entityId: voucherId,
      deletedIds: delKeys,
    );
  }

  void addSaleChallanAndSync(SaleChallan challan) {
    unmarkDeletedId(challan.id, referenceNo: challan.billNo);
    D1SalesLedgerService.unmarkPermanentlyDeleted(challan.id, challan.billNo);

    final cleanBNo = challan.billNo.trim().toUpperCase();
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
    String compKey = "";
    try {
      final targetC = purchaseChallans.firstWhere((item) => item.id == challanId || item.internalNo == challanId || item.billNo == challanId);
      iNo = targetC.internalNo.trim().toUpperCase();
      bNo = targetC.billNo.trim().toUpperCase();
      pId = targetC.partyId.trim().toUpperCase();
      compKey = PurchaseChallanSyncModule.makeCompositeKey(pId, bNo, iNo);
      PurchaseChallanSyncModule.onPurchaseChallanDeleted(targetC, activeStoreToken);
    } catch (_) {}
    D1SalesLedgerService.markPermanentlyDeleted(challanId, bNo, iNo);
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    final List<String> delKeys = [
      challanId,
      if (iNo.isNotEmpty) iNo,
      if (bNo.isNotEmpty) bNo,
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
    purchaseChallans.removeWhere((item) => item.id == challanId || (iNo.isNotEmpty && item.internalNo.trim().toUpperCase() == iNo) || (bNo.isNotEmpty && item.billNo.trim().toUpperCase() == bNo));
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'DELETE_PURCHASE_CHALLAN',
      entityId: challanId,
      deletedIds: delKeys,
    );
  }

  void deleteSaleReturn(String returnId) {
    String bNo = "";
    try {
      final targetR = saleReturns.firstWhere((item) => item.id == returnId || item.billNo == returnId);
      bNo = targetR.billNo.trim().toUpperCase();
    } catch (_) {}
    D1SalesLedgerService.markPermanentlyDeleted(returnId, bNo);
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    final List<String> delKeys = [returnId, if (bNo.isNotEmpty) bNo];
    for (var k in delKeys) {
      localTombstoneRegistry[k] = delTime;
      deletedRecordIds.add(k);
      unmarkedRecordIds.remove(k);
    }
    _saveLocalTombstones();
    saleReturns.removeWhere((item) => item.id == returnId || (bNo.isNotEmpty && item.billNo.trim().toUpperCase() == bNo));
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'RECORD_DELETED',
      entityId: returnId,
      deletedIds: delKeys,
    );
  }

  void deletePurchaseReturn(String returnId) {
    String bNo = "";
    try {
      final targetR = purchaseReturns.firstWhere((item) => item.id == returnId || item.billNo == returnId);
      bNo = targetR.billNo.trim().toUpperCase();
    } catch (_) {}
    D1SalesLedgerService.markPermanentlyDeleted(returnId, bNo);
    final int delTime = DateTime.now().millisecondsSinceEpoch;
    final List<String> delKeys = [returnId, if (bNo.isNotEmpty) bNo];
    for (var k in delKeys) {
      localTombstoneRegistry[k] = delTime;
      deletedRecordIds.add(k);
      unmarkedRecordIds.remove(k);
    }
    _saveLocalTombstones();
    purchaseReturns.removeWhere((item) => item.id == returnId || (bNo.isNotEmpty && item.billNo.trim().toUpperCase() == bNo));
    notifyListeners();
    _autoSyncService.triggerAutoSync(
      action: 'RECORD_DELETED',
      entityId: returnId,
      deletedIds: delKeys,
    );
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
      updatedParty.updatedAt = DateTime.now().millisecondsSinceEpoch;
      updatedParty.version = parties[idx].version + 1;
      parties[idx] = updatedParty;
      notifyListeners();
      _autoSyncService.triggerAutoSync(action: 'PARTY_UPDATED', entityId: updatedParty.id);
    }
  }

  void deleteParty(String partyId) {
    deletedRecordIds.add(partyId);
    _saveLocalTombstones();
    parties.removeWhere((p) => p.id == partyId);
    notifyListeners();
    _autoSyncService.triggerAutoSync(action: 'PARTY_DELETED', entityId: partyId, deletedIds: [partyId]);
  }

  void addParty(Party newParty) {
    String cleanNewName = newParty.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    final int nowTs = DateTime.now().millisecondsSinceEpoch;

    int existingIdx = parties.indexWhere((p) {
      if (newParty.id.isNotEmpty && p.id == newParty.id) return true;
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
        updatedAt: nowTs,
        version: parties[existingIdx].version + 1,
      );
      parties[existingIdx] = newParty;
    } else {
      newParty.updatedAt = nowTs;
      if (newParty.version < 1) newParty.version = 1;
      parties.add(newParty);
    }
    notifyListeners();
    _autoSyncService.triggerAutoSync(action: 'PARTY_SAVED', entityId: newParty.id);
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
    if (type == "SALE" && prefix.trim().toUpperCase() == "INV-") {
      prefix = "W-";
    } else if (type == "PURCHASE" && prefix.trim().toUpperCase() == "PUR-") {
      prefix = "WPUR-";
    }

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
