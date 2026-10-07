// FILE: lib/web_live_sync/sync_protocol/delta_merge_engine.dart
import 'dart:convert';
import '../../../pharoah_manager.dart';
import '../../../models.dart';

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
      String syncId = (cloudMap['sync_id'] ?? cloudMap['id'] ?? '').toString().trim();
      int cloudVersion = int.tryParse(cloudMap['version']?.toString() ?? '1') ?? 1;
      int cloudTimestamp = int.tryParse(cloudMap['updated_at']?.toString() ?? cloudMap['updatedAt']?.toString() ?? '0') ?? 0;
      int cloudIsDeleted = int.tryParse(cloudMap['is_deleted']?.toString() ?? cloudMap['isDeleted']?.toString() ?? (cloudMap['status'] == 'Deleted' || cloudMap['status'] == 'Cancelled' ? '1' : '0')) ?? 0;

      if (syncId.isEmpty) continue;

      // 🛡️ SHIELD 1: Chronological Anti-Zombie Guard (ID ONLY)
      if (localTombstoneRegistry.containsKey(syncId)) {
        int localDeleteTime = localTombstoneRegistry[syncId]!;
        if (localDeleteTime >= cloudTimestamp) {
          continue; // Obsolete lag-data packet dropped securely
        } else if (cloudIsDeleted == 0) {
          localTombstoneRegistry.remove(syncId); // Legit new creation
        }
      }

      int idx = localList.indexWhere((s) => s.syncId == syncId || s.id == syncId);

      if (idx != -1) {
        Sale localSale = localList[idx];
        // Last-Write-Wins (LWW) Check
        if (cloudTimestamp > localSale.updatedAt || (cloudTimestamp == localSale.updatedAt && cloudVersion >= localSale.version) || localSale.updatedAt == 0) {
          if (cloudIsDeleted == 1) {
            localList.removeAt(idx);
            localTombstoneRegistry[syncId] = cloudTimestamp;
          } else {
            localList[idx] = Sale.fromEnvelope(cloudMap); // Safe update
          }
        }
      } else {
        if (cloudIsDeleted == 0) {
          // Gap-filling safety: if an older record with the same billNo exists, replace/remove it
          String bNo = (cloudMap['billNo'] ?? '').toString().trim();
          if (bNo.isNotEmpty) {
            localList.removeWhere((s) => s.billNo == bNo && s.updatedAt <= cloudTimestamp);
          }
          localList.insert(0, Sale.fromEnvelope(cloudMap)); // Safe gap-filling injection
        }
      }
    }
    return localList;
  }

  /// 🛡️ Smartly merges cloud snapshot data with ERP Multi-Node collision prevention,
  /// Anti-Zombie Timestamp Shields, and True LWW safeguards.
  static bool processCloudData(
    PharoahManager ph, 
    Map<String, dynamic> cloudFiles, 
    dynamic localTombstonesOrRegistry, 
    Map<String, String> localHashes
  ) {
    bool hasChanges = false;
    Map<String, int> tombstoneRegistry = {};
    if (localTombstonesOrRegistry is Map<String, int>) {
      tombstoneRegistry = Map<String, int>.from(localTombstonesOrRegistry);
    } else if (localTombstonesOrRegistry is Set<String>) {
      for (var k in localTombstonesOrRegistry) {
        tombstoneRegistry[k] = 0;
      }
    } else if (localTombstonesOrRegistry is Iterable) {
      for (var k in localTombstonesOrRegistry) {
        tombstoneRegistry[k.toString()] = 0;
      }
    }
    // Purge any billNo keys from registry (MANDATE 1)
    tombstoneRegistry.removeWhere((k, _) => k.contains('/'));

    dynamic decodeJson(String fileName) {
      if (cloudFiles.containsKey(fileName) && cloudFiles[fileName] != null) {
        try { return jsonDecode(cloudFiles[fileName]); } catch (_) {}
      }
      return null;
    }

    // 🛡️ Advanced Deep-Compare & Deduplicating Merge Function with True LWW & Anti-Zombie Shields
    bool mergeList<T>(
      List<dynamic>? cloudList,
      List<T> localList,
      String Function(T) getId,
      String Function(T) getBillNo,
      T Function(Map<String, dynamic>) fromMap,
      Map<String, dynamic> Function(T) toMap,
    ) {
      if (cloudList == null) return false;
      bool changed = false;

      // 1. Process Cloud Records with Anti-Zombie Shield
      for (var rawMap in cloudList) {
        if (rawMap is! Map<String, dynamic>) continue;
        final cloudMap = rawMap;
        String id = (cloudMap['id'] ?? cloudMap['sync_id'] ?? '').toString().trim();
        String billNo = (cloudMap['billNo'] ?? cloudMap['internalNo'] ?? cloudMap['voucherNo'] ?? '').toString().trim();
        int cloudVersion = int.tryParse(cloudMap['version']?.toString() ?? '1') ?? 1;
        int cloudTimestamp = int.tryParse(cloudMap['updated_at']?.toString() ?? cloudMap['updatedAt']?.toString() ?? '0') ?? 0;
        int cloudIsDeleted = int.tryParse(cloudMap['is_deleted']?.toString() ?? cloudMap['isDeleted']?.toString() ?? (cloudMap['status'] == 'Deleted' || cloudMap['status'] == 'Cancelled' ? '1' : '0')) ?? 0;

        if (id.isEmpty) continue;

        // 🛡️ SHIELD 1: Anti-Zombie / Tombstone Check (ID ONLY, NEVER billNo)
        int? localDeleteTime = tombstoneRegistry[id];
        if (localDeleteTime != null) {
          if (localDeleteTime >= cloudTimestamp && localDeleteTime > 0) {
            // Google Drive data is older than delete event -> Skip / Drop
            continue; 
          } else if (cloudIsDeleted == 0) {
            // Legitimate newer update found -> unmark tombstone
            tombstoneRegistry.remove(id);
            if (localTombstonesOrRegistry is Set<String>) {
              localTombstonesOrRegistry.remove(id);
            }
          }
        }

        // Local active screen list me check karo (Match by unique ID)
        int idx = localList.indexWhere((e) => getId(e) == id);

        if (idx != -1) {
          var localItem = localList[idx];
          var localMap = toMap(localItem);
          int localTimestamp = (localMap['updated_at'] ?? localMap['updatedAt'] ?? 0).toInt();
          int localVer = (localMap['version'] ?? 1).toInt();

          // 🛡️ SHIELD 2: Last-Write-Wins (LWW) Clock Auditing
          if (cloudTimestamp > localTimestamp || (cloudTimestamp == localTimestamp && cloudVersion >= localVer) || localTimestamp == 0) {
            if (cloudIsDeleted == 1) {
              localList.removeAt(idx);
              tombstoneRegistry[id] = cloudTimestamp;
              changed = true;
            } else {
              localList[idx] = fromMap(cloudMap);
              changed = true;
            }
          }
        } else {
          if (cloudIsDeleted == 0) {
            // Gap-filling safety: if an older record with the same billNo exists, replace it
            if (billNo.isNotEmpty) {
              localList.removeWhere((e) => getBillNo(e) == billNo && (toMap(e)['updatedAt'] ?? 0) <= cloudTimestamp);
            }
            localList.add(fromMap(cloudMap));
            changed = true;
          }
        }
      }

      // 2. Final De-duplication Pass: Keep only 1 record per BillNo (keep newest)
      Map<String, T> uniqueByBillNo = {};
      for (var item in localList) {
        String bNo = getBillNo(item);
        if (bNo.isNotEmpty) {
          if (!uniqueByBillNo.containsKey(bNo)) {
            uniqueByBillNo[bNo] = item;
          } else {
            var existing = uniqueByBillNo[bNo]!;
            int existingUpdated = (toMap(existing)['updated_at'] ?? toMap(existing)['updatedAt'] ?? 0).toInt();
            int currentUpdated = (toMap(item)['updated_at'] ?? toMap(item)['updatedAt'] ?? 0).toInt();
            if (currentUpdated >= existingUpdated) {
              uniqueByBillNo[bNo] = item;
            }
          }
        }
      }

      if (uniqueByBillNo.isNotEmpty && uniqueByBillNo.length < localList.length) {
        localList.clear();
        localList.addAll(uniqueByBillNo.values);
        changed = true;
      }

      return changed;
    }

    bool cSales = mergeList<Sale>(
      decodeJson('sales.json'), 
      ph.sales, 
      (e) => e.id, 
      (e) => e.billNo, 
      (m) => Sale.fromMap(m), 
      (e) => e.toMap()
    );

    bool cPurc = mergeList<Purchase>(
      decodeJson('purc.json'), 
      ph.purchases, 
      (e) => e.id, 
      (e) => e.billNo.isNotEmpty ? e.billNo : e.internalNo, 
      (m) => Purchase.fromMap(m), 
      (e) => e.toMap()
    );

    bool cVouc = mergeList<Voucher>(
      decodeJson('vouc.json'), 
      ph.vouchers, 
      (e) => e.id, 
      (e) => e.voucherNo, 
      (m) => Voucher.fromMap(m), 
      (e) => e.toMap()
    );

    bool cSCh = mergeList<SaleChallan>(
      decodeJson('s_challan.json'), 
      ph.saleChallans, 
      (e) => e.id, 
      (e) => e.billNo, 
      (m) => SaleChallan.fromMap(m), 
      (e) => e.toMap()
    );

    bool cPCh = mergeList<PurchaseChallan>(
      decodeJson('p_challan.json'), 
      ph.purchaseChallans, 
      (e) => e.id, 
      (e) => e.internalNo.isNotEmpty ? e.internalNo : e.billNo, 
      (m) => PurchaseChallan.fromMap(m), 
      (e) => e.toMap()
    );

    bool cSRet = mergeList<SaleReturn>(
      decodeJson('s_return.json'), 
      ph.saleReturns, 
      (e) => e.id, 
      (e) => e.billNo, 
      (m) => SaleReturn.fromMap(m), 
      (e) => e.toMap()
    );

    bool cPRet = mergeList<PurchaseReturn>(
      decodeJson('p_return.json'), 
      ph.purchaseReturns, 
      (e) => e.id, 
      (e) => e.billNo, 
      (m) => PurchaseReturn.fromMap(m), 
      (e) => e.toMap()
    );

    // Master Records Sync with LWW
    var rawParts = decodeJson('parts.json') as List?;
    if (rawParts != null) {
      for (var rawPart in rawParts) {
        final partMap = rawPart as Map<String, dynamic>;
        String cleanName = (partMap['name'] ?? '').toString().replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        if (cleanName.isEmpty) continue;
        int existingIdx = ph.parties.indexWhere((p) => p.id == partMap['id']);
        if (existingIdx != -1) {
          String lJson = jsonEncode(ph.parties[existingIdx].toMap());
          String cJson = jsonEncode(partMap);
          if (lJson != cJson) {
            int cUpdated = (partMap['updated_at'] ?? partMap['updatedAt'] ?? 0).toInt();
            int lUpdated = ph.parties[existingIdx].updatedAt;
            if (cUpdated > lUpdated) {
              ph.parties[existingIdx] = Party.fromMap(partMap);
              hasChanges = true;
            }
          }
        } else {
          ph.parties.add(Party.fromMap(partMap));
          hasChanges = true;
        }
      }
    }

    var rawMeds = decodeJson('meds.json') as List?;
    if (rawMeds != null) {
      for (var rawMed in rawMeds) {
        final medMap = rawMed as Map<String, dynamic>;
        String cleanName = (medMap['name'] ?? '').toString().replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        if (cleanName.isEmpty) continue;
        int existingIdx = ph.medicines.indexWhere((m) => m.id == medMap['id']);
        if (existingIdx != -1) {
          String lJson = jsonEncode(ph.medicines[existingIdx].toMap());
          String cJson = jsonEncode(medMap);
          if (lJson != cJson) {
            int cUpdated = (medMap['updated_at'] ?? medMap['updatedAt'] ?? 0).toInt();
            int lUpdated = ph.medicines[existingIdx].updatedAt;
            if (cUpdated > lUpdated) {
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

    return hasChanges || cSales || cPurc || cVouc || cSCh || cPCh || cSRet || cPRet;
  }
}
