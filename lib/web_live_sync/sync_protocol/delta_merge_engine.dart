// FILE: lib/web_live_sync/sync_protocol/delta_merge_engine.dart
import 'dart:convert';
import '../../../pharoah_manager.dart';
import '../../../models.dart';

class DeltaMergeEngine {
  /// 🛡️ Smartly merges cloud data with ERP Multi-Node collision prevention,
  /// Anti-Zombie Timestamp Shields, and True LWW safeguards.
  static bool processCloudData(
    PharoahManager ph, 
    Map<String, dynamic> cloudFiles, 
    Map<String, int> localTombstoneRegistry, 
    Map<String, String> localHashes
  ) {
    bool hasChanges = false;

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

        // 🛡️ SHIELD 1: Anti-Zombie / Tombstone Check with Microsecond/Millisecond Timestamp
        // Agar ye bill local me delete ho chuka hai aur uski delete time remote clock se nayi hai,
        // to Google Drive ke purane snapshot ko direct DROP (Ignore) kar do!
        int? localDeleteTime = localTombstoneRegistry[id] ?? (billNo.isNotEmpty ? localTombstoneRegistry[billNo] : null);
        if (localDeleteTime != null) {
          if (localDeleteTime >= cloudTimestamp) {
            // Google Drive ka data purana hai, aur bill delete ho chuka hai -> Skip / Drop
            continue; 
          } else if (cloudIsDeleted == 0) {
            // Agar remote timestamp sach me naya hai aur status active hai, tabhi tombstone se azad karo
            localTombstoneRegistry.remove(id);
            if (billNo.isNotEmpty) localTombstoneRegistry.remove(billNo);
          }
        }

        // Local active screen list me check karo
        int idx = localList.indexWhere((e) => getId(e) == id || (billNo.isNotEmpty && getBillNo(e) == billNo));

        if (idx != -1) {
          var localItem = localList[idx];
          var localMap = toMap(localItem);
          int localTimestamp = (localMap['updated_at'] ?? localMap['updatedAt'] ?? 0).toInt();
          int localVer = (localMap['version'] ?? 1).toInt();

          // 🛡️ SHIELD 2: Last-Write-Wins (LWW) Clock Auditing
          if (cloudTimestamp > localTimestamp || (cloudTimestamp == localTimestamp && cloudVersion >= localVer) || localTimestamp == 0) {
            if (cloudIsDeleted == 1) {
              // Server ya backup se delete confirm hua -> List se udao
              localList.removeAt(idx);
              localTombstoneRegistry[id] = cloudTimestamp;
              if (billNo.isNotEmpty) localTombstoneRegistry[billNo] = cloudTimestamp;
              changed = true;
            } else {
              // Legitimate newer update found -> Overwrite local model state
              localList[idx] = fromMap(cloudMap);
              changed = true;
            }
          }
        } else {
          // 🧠 THE TRAP BYPASSED LOGIC:
          // Agar remote data local list me nahi hai, to direct add mat karo!
          // Pehle check karo ki kya wo deleted packet to nahi hai?
          if (cloudIsDeleted == 0) {
            // Google Drive se aaya data tabhi add hoga agar wo deleted nahi hai
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

      if (uniqueByBillNo.length < localList.length) {
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
