import '../../logic/app_settings_model.dart';
import '../../sync_core/modules/batch_delta_merge_module.dart';
import "../../sync_core/modules/medicine_sync_module.dart";
import "../../sync_core/modules/company_sync_module.dart";
import "../../sync_core/modules/salt_sync_module.dart";
import "../../sync_core/modules/route_sync_module.dart";
import "../../sync_core/modules/gst_diary_sync_module.dart";
import "../../../sync_core/modules/party_sync_module.dart";
import "../../../sync_core/d1_sales_ledger_service.dart";
// FILE: lib/web_live_sync/sync_protocol/delta_merge_engine.dart

import "dart:convert";
import "../../../pharoah_manager.dart";
import "../../../models.dart";
import "../../sync_core/modules/purchase_sync_module.dart";
import "../../sync_core/modules/purchase_challan_sync_module.dart";

/// 🛡️ THE ENHANCED DELTA MERGE ENGINE RECONCILER
/// Bridges Google Drive snapshots and D1 JSON batch inputs without ghost overwrites.
class DeltaMergeEngine {
  /// 🛡️ Dedicated Incoming Delta Batch Merger for Sales
  static List<Sale> mergeIncomingDelta({
    required List<Sale> localList,
    required List<dynamic> incomingCloudBatch,
    required Map<String, int> localTombstoneRegistry,
  }) {
    for (var rawCloudMap in incomingCloudBatch) {
      if (rawCloudMap is! Map<String, dynamic>) continue;
      final cloudMap = rawCloudMap;

      String syncId = (cloudMap["sync_id"] ?? cloudMap["id"] ?? "").toString().trim();
      int cloudVersion = int.tryParse(cloudMap["version"]?.toString() ?? "1") ?? 1;
      int cloudTimestamp = int.tryParse(cloudMap["updated_at"]?.toString() ?? cloudMap["updatedAt"]?.toString() ?? "0") ?? 0;
      int cloudIsDeleted = int.tryParse(cloudMap["is_deleted"]?.toString() ?? cloudMap["isDeleted"]?.toString() ?? (cloudMap["status"] == "Deleted" ? "1" : "0")) ?? 0;

      if (syncId.isEmpty) continue;

      String billNo = (cloudMap["billNo"] ?? cloudMap["internalNo"] ?? "").toString().trim();
      String cleanBill = billNo.toUpperCase();

      if (D1SalesLedgerService.isBillDeleted(syncId, billNo)) continue;

      // 🛡️ SHIELD 1: Anti-Zombie Tombstone Check
      if (localTombstoneRegistry.containsKey(syncId) || (cleanBill.isNotEmpty && localTombstoneRegistry.containsKey(cleanBill))) {
        continue; // Dropped securely, never resurrect from lagging cloud packet
      }

      int idx = localList.indexWhere((s) => s.syncId == syncId || s.id == syncId || (cleanBill.isNotEmpty && s.billNo.trim().toUpperCase() == cleanBill));

      if (idx != -1) {
        Sale localSale = localList[idx];

        if (cloudIsDeleted == 1) {
          localList.removeAt(idx);
          localTombstoneRegistry[syncId] = cloudTimestamp > 0 ? cloudTimestamp : DateTime.now().millisecondsSinceEpoch;
          if (cleanBill.isNotEmpty) localTombstoneRegistry[cleanBill] = localTombstoneRegistry[syncId]!;
        } else if (cloudVersion > localSale.version || (cloudVersion == localSale.version && cloudTimestamp >= localSale.updatedAt) || localSale.updatedAt == 0) {
          localList[idx] = Sale.fromEnvelope(cloudMap);
        }
      } else {
        if (cloudIsDeleted == 0) {
          if (cleanBill.isNotEmpty) {
            localList.removeWhere((s) => s.billNo.trim().toUpperCase() == cleanBill && s.updatedAt <= cloudTimestamp);
          }
          localList.insert(0, Sale.fromEnvelope(cloudMap));
        }
      }
    }
    return localList;
  }

  /// 🛡️ Smartly merges cloud snapshot data with ERP Multi-Node collision prevention,
  /// Anti-Zombie Multi-Key Shields, and True LWW safeguards.
  static bool processCloudData(
    PharoahManager ph, 
    Map<String, dynamic> cloudFiles, 
    dynamic localTombstonesOrRegistry, 
    Map<String, String> localHashes
  ) {
    bool hasChanges = false;
    final int nowEpoch = DateTime.now().millisecondsSinceEpoch;

    Map<String, int> tombstoneRegistry = {};
    if (localTombstonesOrRegistry is Map<String, int>) {
      tombstoneRegistry = Map<String, int>.from(localTombstonesOrRegistry);
    } else if (localTombstonesOrRegistry is Set<String>) {
      for (var k in localTombstonesOrRegistry) {
        tombstoneRegistry[k] = nowEpoch;
      }
    } else if (localTombstonesOrRegistry is Iterable) {
      for (var k in localTombstonesOrRegistry) {
        tombstoneRegistry[k.toString()] = nowEpoch;
      }
    }

    dynamic decodeJson(String fileName) {
      if (cloudFiles.containsKey(fileName) && cloudFiles[fileName] != null) {
        try { return jsonDecode(cloudFiles[fileName]); } catch (_) {}
      }
      return null;
    }

    // 🛡️ 0. MASTER RECORDS (PARTIES & MEDICINES) MERGE FIRST TO ENSURE FOREIGN KEY INTEGRITY
    var rawParts = decodeJson("parts.json") as List?;
    if (rawParts != null) {
      bool cParts = PartySyncModule.mergePartyList(
        cloudPartyList: rawParts,
        localPartyList: ph.parties,
        tombstoneRegistry: tombstoneRegistry,
      );
      if (cParts) hasChanges = true;
    }

    var rawMeds = decodeJson("meds.json") as List?;
    if (rawMeds != null) {
      MedicineSyncModule.mergeMedicineList(
        cloudMedicineList: rawMeds,
        localMedicineList: ph.medicines,
        tombstoneRegistry: tombstoneRegistry,
        deletedRecordIds: tombstoneRegistry.keys.toSet(),
      );
      hasChanges = true;
    }

    // 🛡️ Advanced Deep-Compare & Deduplicating Merge Function with Multi-Key Anti-Zombie Shields
    bool mergeList<T>(
      List<dynamic>? cloudList,
      List<T> localList,
      String Function(T) getId,
      String Function(T) getBillNo,
      T Function(Map<String, dynamic>) fromMap,
      Map<String, dynamic> Function(T) toMap,
      [String Function(Map<String, dynamic>)? getCloudCompositeKey]
    ) {
      if (cloudList == null) return false;
      bool changed = false;

      // 1. Process Cloud Records with Anti-Zombie Shield
      for (var rawMap in cloudList) {
        if (rawMap is! Map<String, dynamic>) continue;
        final cloudMap = rawMap;

        String id = (cloudMap["id"] ?? cloudMap["sync_id"] ?? "").toString().trim();
        String billNo = (cloudMap["billNo"] ?? cloudMap["voucherNo"] ?? "").toString().trim();
        String internalNo = (cloudMap["internalNo"] ?? "").toString().trim();
        int cloudVersion = int.tryParse(cloudMap["version"]?.toString() ?? "1") ?? 1;
        int cloudTimestamp = int.tryParse(cloudMap["updated_at"]?.toString() ?? cloudMap["updatedAt"]?.toString() ?? "0") ?? 0;
        int cloudIsDeleted = int.tryParse(cloudMap["is_deleted"]?.toString() ?? cloudMap["isDeleted"]?.toString() ?? (cloudMap["status"] == "Deleted" || cloudMap["status"] == "Cancelled" ? "1" : "0")) ?? 0;

        if (id.isEmpty) continue;

        // 🛡️ Multi-Key Anti-Zombie Check: ID + FY-Scoped Secondary Keys (InternalNo, BillNo, CompositeKey)
        final String activeFy = ph.currentFY.trim();
        final bool isCompositeDoc = getCloudCompositeKey != null;
        String bNoKey = isCompositeDoc ? billNo : billNo.toUpperCase();
        String intNoKey = internalNo.toUpperCase();
        String partyIdKey = (cloudMap["partyId"] ?? "").toString().trim().toUpperCase();
        String compKey2 = (partyIdKey.isNotEmpty && bNoKey.isNotEmpty) ? "${partyIdKey}_$bNoKey" : "";
        final compositeKey = getCloudCompositeKey?.call(cloudMap).trim() ?? "";

        final String scopedBNo = D1SalesLedgerService.scopeSecondaryKey(bNoKey, activeFy, isCompositeDoc);
        final String scopedIntNo = D1SalesLedgerService.scopeSecondaryKey(intNoKey, activeFy);
        final String scopedComp2 = D1SalesLedgerService.scopeSecondaryKey(compKey2, activeFy, true);
        final String scopedComp3 = D1SalesLedgerService.scopeSecondaryKey(compositeKey, activeFy, true);

        // 🛡️ 1. PERMANENT D1 GRAVESTONE CHECK (Scoped by activeFy so series numbers never collide across FYs)
        if (getCloudCompositeKey != null) {
          if (D1SalesLedgerService.isPurchaseDeleted(id, partyIdKey, billNo, internalNo, activeFy)) {
            continue;
          }
        } else {
          if (D1SalesLedgerService.isBillDeleted(id, billNo, internalNo, activeFy)) {
            continue;
          }
        }

        // 🛡️ 2. STRICT TOMBSTONE REGISTRY CHECK (Immutable ID vs FY-Scoped Chronological Series/Composite Keys)
        final int idDelTs = tombstoneRegistry[id] ?? tombstoneRegistry[id.toUpperCase()] ?? 0;
        if (idDelTs > 0 && (cloudTimestamp == 0 || idDelTs >= cloudTimestamp)) {
          // Exact UUID was deleted at or after this record timestamp — never resurrect it
          continue;
        }
        final String scopedComp2Upper = scopedComp2.isNotEmpty ? scopedComp2.toUpperCase() : "";
        final String scopedComp3Upper = scopedComp3.isNotEmpty ? scopedComp3.toUpperCase() : "";
        final int secDelTs = (scopedIntNo.isNotEmpty ? tombstoneRegistry[scopedIntNo] : null) ??
            (scopedComp3.isNotEmpty ? tombstoneRegistry[scopedComp3] : null) ??
            (scopedComp2.isNotEmpty ? tombstoneRegistry[scopedComp2] : null) ??
            (scopedComp3Upper.isNotEmpty ? tombstoneRegistry[scopedComp3Upper] : null) ??
            (scopedComp2Upper.isNotEmpty ? tombstoneRegistry[scopedComp2Upper] : null) ??
            (getCloudCompositeKey == null && scopedBNo.isNotEmpty ? tombstoneRegistry[scopedBNo] : null) ?? 0;
        if (secDelTs > 0 && (cloudTimestamp == 0 || secDelTs >= cloudTimestamp)) {
          // Secondary key in this FY was deleted at or after this record timestamp — block stale snapshot record
          continue;
        }

        // Match in active local list
        int idx = localList.indexWhere((e) {
          if (getId(e) == id) return true;
          final localBNo = isCompositeDoc ? getBillNo(e).trim() : getBillNo(e).trim().toUpperCase();
          if (compositeKey.isNotEmpty && localBNo == compositeKey) return true;
          if (intNoKey.isNotEmpty && (localBNo == intNoKey || localBNo == "INT:$intNoKey" || localBNo.endsWith("_$intNoKey"))) return true;
          if (!isCompositeDoc && bNoKey.isNotEmpty && localBNo == bNoKey) return true;
          return false;
        });

        if (cloudIsDeleted == 1) {
          if (idx != -1) {
            localList.removeAt(idx);
            changed = true;
          }
          final int delTs = cloudTimestamp > 0 ? cloudTimestamp : nowEpoch;
          tombstoneRegistry[id] = delTs;
          tombstoneRegistry[id.toUpperCase()] = delTs;
          if (getCloudCompositeKey == null && scopedBNo.isNotEmpty) tombstoneRegistry[scopedBNo] = delTs;
          if (scopedIntNo.isNotEmpty) tombstoneRegistry[scopedIntNo] = delTs;
          if (scopedComp2.isNotEmpty) tombstoneRegistry[scopedComp2] = delTs;
          if (scopedComp3.isNotEmpty) tombstoneRegistry[scopedComp3] = delTs;
          if (getCloudCompositeKey != null) {
            D1SalesLedgerService.markPurchasePermanentlyDeleted(id, partyIdKey, billNo, internalNo, activeFy);
          } else {
            D1SalesLedgerService.markPermanentlyDeleted(id, billNo, internalNo, activeFy);
          }
          continue;
        }

        if (idx != -1) {
          var localItem = localList[idx];
          var localMap = toMap(localItem);
          int localTimestamp = (localMap["updated_at"] ?? localMap["updatedAt"] ?? 0).toInt();
          int localVer = (localMap["version"] ?? 1).toInt();

          // 🛡️ Last-Write-Wins (LWW) Clock Auditing
          if (cloudVersion > localVer ||
              (cloudVersion == localVer && cloudTimestamp >= localTimestamp) ||
              (getId(localItem) != id && cloudTimestamp > localTimestamp) ||
              localTimestamp == 0) {
            localList[idx] = fromMap(cloudMap);
            changed = true;
          }
        } else {
          localList.insert(0, fromMap(cloudMap));
          changed = true;
        }
      }

      // 2. Safe Deduplication Pass (preserving items without bill numbers & preventing Cross-Bill Collisions)
      Map<String, T> uniqueByBillNo = {};
      List<T> nonBillItems = [];

      for (var item in localList) {
        String bNo = getCloudCompositeKey != null ? getBillNo(item).trim() : getBillNo(item).trim().toUpperCase();
        String itemId = getId(item).trim();
        String dedupKey = bNo.isNotEmpty ? bNo : (itemId.isNotEmpty ? "ID:$itemId" : "");

        if (dedupKey.isNotEmpty) {
          if (!uniqueByBillNo.containsKey(dedupKey)) {
            uniqueByBillNo[dedupKey] = item;
          } else {
            var existing = uniqueByBillNo[dedupKey]!;
            int existingUpdated = (toMap(existing)["updated_at"] ?? toMap(existing)["updatedAt"] ?? 0).toInt();
            int currentUpdated = (toMap(item)["updated_at"] ?? toMap(item)["updatedAt"] ?? 0).toInt();
            int existingVer = (toMap(existing)["version"] ?? 1).toInt();
            int currentVer = (toMap(item)["version"] ?? 1).toInt();
            if (currentVer > existingVer || (currentVer == existingVer && currentUpdated >= existingUpdated)) {
              uniqueByBillNo[dedupKey] = item;
            }
          }
        } else {
          nonBillItems.add(item);
        }
      }

      final deduplicated = [...uniqueByBillNo.values, ...nonBillItems];
      if (deduplicated.length != localList.length) {
        localList.clear();
        localList.addAll(deduplicated);
        changed = true;
      }

      return changed;
    }

    bool cSales = mergeList<Sale>(
      decodeJson("sales.json"), 
      ph.sales, 
      (e) => e.id, 
      (e) => e.billNo, 
      (m) => Sale.fromMap(m), 
      (e) => e.toMap()
    );
    bool cPurc = mergeList<Purchase>(
      decodeJson("purc.json"), 
      ph.purchases, 
      (e) => e.id, 
      (e) {
        final comp = PurchaseSyncModule.getCompositeKey(e);
        if (comp.isNotEmpty) return comp;
        final intNo = e.internalNo.trim().toUpperCase();
        if (intNo.isNotEmpty) return "INT:$intNo";
        return "ID:${e.id}";
      }, 
      (m) => Purchase.fromMap(m),
      (e) => e.toMap(),
      (m) => PurchaseSyncModule.makeCompositeKey(
        (m["partyId"] ?? "").toString(),
        (m["billNo"] ?? "").toString(),
        (m["internalNo"] ?? "").toString(),
      )
    );
    bool cVouc = mergeList<Voucher>(
      decodeJson("vouc.json"), 
      ph.vouchers, 
      (e) => e.id, 
      (e) => e.voucherNo, 
      (m) => Voucher.fromMap(m), 
      (e) => e.toMap()
    );
    bool cSCh = mergeList<SaleChallan>(
      decodeJson("s_challan.json"), 
      ph.saleChallans, 
      (e) => e.id, 
      (e) => e.billNo, 
      (m) => SaleChallan.fromMap(m), 
      (e) => e.toMap()
    );
    bool cPCh = mergeList<PurchaseChallan>(
      decodeJson("p_challan.json"),
      ph.purchaseChallans,
      (e) => e.id,
      (e) {
        final comp = PurchaseChallanSyncModule.makeCompositeKey(e.partyId, e.billNo, e.internalNo);
        if (comp.isNotEmpty) return comp;
        final intNo = e.internalNo.trim().toUpperCase();
        if (intNo.isNotEmpty) return "INT:$intNo";
        return "ID:${e.id}";
      },
      (m) => PurchaseChallan.fromMap(m),
      (e) => e.toMap(),
      (m) => PurchaseChallanSyncModule.makeCompositeKey(
        (m["partyId"] ?? "").toString(),
        (m["billNo"] ?? "").toString(),
        (m["internalNo"] ?? "").toString(),
      ),
    );
    bool cSRet = mergeList<SaleReturn>(
      decodeJson("s_return.json"), 
      ph.saleReturns, 
      (e) => e.id, 
      (e) => e.billNo, 
      (m) => SaleReturn.fromMap(m), 
      (e) => e.toMap()
    );
    bool cPRet = mergeList<PurchaseReturn>(
      decodeJson("p_return.json"), 
      ph.purchaseReturns, 
      (e) => e.id, 
      (e) => "${e.distributorName.trim().toUpperCase()}_${e.billNo.trim()}", 
      (m) => PurchaseReturn.fromMap(m), 
      (e) => e.toMap()
    );

        // 🛡️ Upgraded Batch History Delta Merge with Tombstone Filtering (#PH-REV-764)
    bool cBats = false;
    final rawBatsJson = cloudFiles['bats.json'];
    if (rawBatsJson != null) {
      final sanitizedBats = BatchDeltaMergeModule.filterTombstonedBatchJson(
        rawBatsJson.toString(),
        tombstones: tombstoneRegistry.keys,
        registry: tombstoneRegistry,
      );
      cBats = BatchDeltaMergeModule.mergeBatchHistoryFromCloudJson(
        targetBatchHistory: ph.batchHistory,
        incomingJson: sanitizedBats,
        tombstones: tombstoneRegistry.keys,
        registry: tombstoneRegistry,
      );
    }

    // 🛡️ Merge AppConfig (config.json) with LWW & Field Diffing (#PH-REV-765)
    bool cConfig = false;
    final rawConfigJson = cloudFiles['config.json'];
    if (rawConfigJson != null) {
      try {
        final dynamic decodedCfg = rawConfigJson is String ? jsonDecode(rawConfigJson) : rawConfigJson;
        if (decodedCfg is Map) {
          final incomingCfg = AppConfig.fromMap(Map<String, dynamic>.from(decodedCfg));
          final localCfg = ph.config;
          final bool isDiff =
              incomingCfg.developerPassword != localCfg.developerPassword ||
              incomingCfg.userMasterPin != localCfg.userMasterPin ||
              incomingCfg.developerAllowBatchHistoryToUser != localCfg.developerAllowBatchHistoryToUser ||
              incomingCfg.userEnableBatchHistory != localCfg.userEnableBatchHistory ||
              incomingCfg.developerAllowGstDiaryToUser != localCfg.developerAllowGstDiaryToUser ||
              incomingCfg.userEnableGstDiary != localCfg.userEnableGstDiary ||
              incomingCfg.printFormat != localCfg.printFormat ||
              incomingCfg.isArchitectMode != localCfg.isArchitectMode ||
              incomingCfg.termsAndConditions != localCfg.termsAndConditions ||
              incomingCfg.showLogo != localCfg.showLogo ||
              incomingCfg.logoPath != localCfg.logoPath ||
              incomingCfg.showTerms != localCfg.showTerms ||
              incomingCfg.showStaffSign != localCfg.showStaffSign ||
              incomingCfg.signLabel != localCfg.signLabel ||
              incomingCfg.showCustomerSignChallan != localCfg.showCustomerSignChallan ||
              incomingCfg.showQrCode != localCfg.showQrCode ||
              incomingCfg.qrCodePath != localCfg.qrCodePath ||
              incomingCfg.bankAccName != localCfg.bankAccName ||
              incomingCfg.bankAccNumber != localCfg.bankAccNumber ||
              incomingCfg.bankIfsc != localCfg.bankIfsc ||
              incomingCfg.bankNameBranch != localCfg.bankNameBranch ||
              incomingCfg.isMailActive != localCfg.isMailActive ||
              incomingCfg.smtpMailID != localCfg.smtpMailID ||
              incomingCfg.smtpMailPass != localCfg.smtpMailPass ||
              incomingCfg.smtpHost != localCfg.smtpHost ||
              incomingCfg.smtpPort != localCfg.smtpPort ||
              incomingCfg.caName != localCfg.caName ||
              incomingCfg.caMailID != localCfg.caMailID ||
              incomingCfg.caPhone != localCfg.caPhone ||
              incomingCfg.isAuditMode != localCfg.isAuditMode;
          if (incomingCfg.updatedAt > localCfg.updatedAt ||
              incomingCfg.version > localCfg.version ||
              (localCfg.updatedAt == 0 && isDiff)) {
            ph.config = incomingCfg;
            cConfig = true;
          }
        }
      } catch (_) {}
    }

    // 🛡️ Merge Company, Salt & Route Masters with LWW & Cascade Updates (#PH-REV-768)
    bool cComps = CompanySyncModule.mergeCompanyList(
      cloudCompanyList: decodeJson("comps.json"),
      localCompanyList: ph.companies,
      tombstoneRegistry: tombstoneRegistry,
      medicines: ph.medicines,
      shortages: ph.shortages,
    );
    bool cSalts = SaltSyncModule.mergeSaltList(
      cloudSaltList: decodeJson("salts.json"),
      localSaltList: ph.salts,
      tombstoneRegistry: tombstoneRegistry,
      medicines: ph.medicines,
    );
    bool cRouts = RouteSyncModule.mergeRouteList(
      cloudRouteList: decodeJson("routs.json"),
      localRouteList: ph.routes,
      tombstoneRegistry: tombstoneRegistry,
      parties: ph.parties,
    );
    bool cGstSessions = GstDiarySyncModule.mergeSessionList(
      cloudSessionList: decodeJson("gst_sessions.json"),
      localSessionList: ph.gstDiarySessions,
      tombstoneRegistry: tombstoneRegistry,
    );

    final int beforePurgeGhost = ph.sales.length;
    ph.sales.removeWhere((s) =>
        s.id.startsWith('SESS_') ||
        s.id == 'APP_CONFIG_MASTER' ||
        s.billNo.trim().isEmpty ||
        (s.items.isEmpty && s.totalAmount <= 0));
    final bool ghostPurged = ph.sales.length != beforePurgeGhost;

    final anyChanged = hasChanges || ghostPurged || cSales || cPurc || cVouc || cSCh || cPCh || cSRet || cPRet || cBats || cConfig || cComps || cSalts || cRouts || cGstSessions;
    if (anyChanged) {
      try {
        ph.autoHydrateBatchHistoryFromTransactions();
      } catch (_) {}
    }
    return anyChanged;
  }
}
