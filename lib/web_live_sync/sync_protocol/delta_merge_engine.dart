import "../../../sync_core/modules/party_sync_module.dart";
import "../../../sync_core/d1_sales_ledger_service.dart";
// FILE: lib/web_live_sync/sync_protocol/delta_merge_engine.dart

import "dart:convert";
import "../../../pharoah_manager.dart";
import "../../../models.dart";
import "../../sync_core/modules/purchase_sync_module.dart";

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
      int cloudIsDeleted = int.tryParse(cloudMap["is_deleted"]?.toString() ?? cloudMap["isDeleted"]?.toString() ?? (cloudMap["status"] == "Deleted" || cloudMap["status"] == "Cancelled" ? "1" : "0")) ?? 0;

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
      for (var rawMed in rawMeds) {
        final medMap = rawMed as Map<String, dynamic>;
        String cleanName = (medMap["name"] ?? "").toString().replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
        if (cleanName.isEmpty) continue;
        int existingIdx = ph.medicines.indexWhere((m) => m.id == medMap["id"]);
        if (existingIdx != -1) {
          String lJson = jsonEncode(ph.medicines[existingIdx].toMap());
          String cJson = jsonEncode(medMap);
          if (lJson != cJson) {
            int cUpdated = int.tryParse((medMap["updated_at"] ?? medMap["updatedAt"] ?? 0).toString()) ?? 0;
            int lUpdated = ph.medicines[existingIdx].updatedAt;
            if (cUpdated >= lUpdated || lUpdated == 0) {
              ph.medicines[existingIdx] = Medicine.fromMap(medMap);
              hasChanges = true;
            }
          }
        } else {
          ph.medicines.add(Medicine.fromMap(medMap));
          hasChanges = true;
        }
      }
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

        // 🛡️ Multi-Key Anti-Zombie Check: ID, InternalNo, BillNo, CompositeKey
        String bNoKey = billNo.toUpperCase();
        String intNoKey = internalNo.toUpperCase();
        String partyIdKey = (cloudMap["partyId"] ?? "").toString().trim().toUpperCase();
        String compKey2 = (partyIdKey.isNotEmpty && bNoKey.isNotEmpty) ? "${partyIdKey}_$bNoKey" : "";
        final compositeKey = getCloudCompositeKey?.call(cloudMap).trim().toUpperCase() ?? "";

        // 🛡️ 1. PERMANENT D1 GRAVESTONE CHECK (Never resurrect deleted records from lagging Drive files)
        if (getCloudCompositeKey != null) {
          if (D1SalesLedgerService.isPurchaseDeleted(id, partyIdKey, billNo, internalNo)) {
            continue;
          }
        } else {
          if (D1SalesLedgerService.isBillDeleted(id, billNo, internalNo)) {
            continue;
          }
        }

        // 🛡️ 2. STRICT TOMBSTONE REGISTRY CHECK (Immutable ID vs Chronological Series/Composite Keys)
        final int idDelTs = tombstoneRegistry[id] ?? tombstoneRegistry[id.toUpperCase()] ?? 0;
        if (idDelTs > 0) {
          // Exact UUID was deleted — never resurrect it
          continue;
        }
        final int secDelTs = (intNoKey.isNotEmpty ? tombstoneRegistry[intNoKey] : null) ??
            (compositeKey.isNotEmpty ? tombstoneRegistry[compositeKey] : null) ??
            (compKey2.isNotEmpty ? tombstoneRegistry[compKey2] : null) ??
            (getCloudCompositeKey == null && bNoKey.isNotEmpty ? tombstoneRegistry[bNoKey] : null) ?? 0;
        if (secDelTs > 0 && (cloudTimestamp == 0 || secDelTs >= cloudTimestamp)) {
          // Secondary key was deleted at or after this record timestamp — block stale snapshot record
          continue;
        }

        // Match in active local list
        int idx = localList.indexWhere((e) {
          if (getId(e) == id) return true;
          final localBNo = getBillNo(e).trim().toUpperCase();
          if (compositeKey.isNotEmpty && localBNo == compositeKey) return true;
          if (intNoKey.isNotEmpty && (localBNo == intNoKey || localBNo == "INT:$intNoKey" || localBNo.endsWith("_$intNoKey"))) return true;
          if (getCloudCompositeKey == null && bNoKey.isNotEmpty && localBNo == bNoKey) return true;
          return false;
        });

        if (cloudIsDeleted == 1) {
          if (idx != -1) {
            localList.removeAt(idx);
            changed = true;
          }
          tombstoneRegistry[id] = cloudTimestamp > 0 ? cloudTimestamp : nowEpoch;
          tombstoneRegistry[id.toUpperCase()] = tombstoneRegistry[id]!;
          if (getCloudCompositeKey == null && bNoKey.isNotEmpty) tombstoneRegistry[bNoKey] = tombstoneRegistry[id]!;
          if (intNoKey.isNotEmpty) tombstoneRegistry[intNoKey] = tombstoneRegistry[id]!;
          if (compKey2.isNotEmpty) tombstoneRegistry[compKey2] = tombstoneRegistry[id]!;
          if (compositeKey.isNotEmpty) tombstoneRegistry[compositeKey] = tombstoneRegistry[id]!;
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
        String bNo = getBillNo(item).trim().toUpperCase();
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
      (e) => e.internalNo.isNotEmpty ? e.internalNo : "${e.partyId.trim().toUpperCase()}_${e.billNo.trim().toUpperCase()}", 
      (m) => PurchaseChallan.fromMap(m), 
      (e) => e.toMap()
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
      (e) => "${e.distributorName.trim().toUpperCase()}_${e.billNo.trim().toUpperCase()}", 
      (m) => PurchaseReturn.fromMap(m), 
      (e) => e.toMap()
    );

    final anyChanged = hasChanges || cSales || cPurc || cVouc || cSCh || cPCh || cSRet || cPRet;
    if (anyChanged) {
      try {
        ph.autoHydrateBatchHistoryFromTransactions();
      } catch (_) {}
    }
    return anyChanged;
  }
}
