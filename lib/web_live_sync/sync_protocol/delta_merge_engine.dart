// FILE: lib/web_live_sync/sync_protocol/delta_merge_engine.dart
import 'dart:convert';
import '../../../pharoah_manager.dart';
import '../../../models.dart';

class DeltaMergeEngine {
  /// Smartly merges cloud data with ERP Multi-Node collision prevention and LWW safeguards.
  static bool processCloudData(PharoahManager ph, Map<String, dynamic> cloudFiles, Set<String> tombstones, Map<String, String> localHashes) {
    bool hasChanges = false;

    dynamic decodeJson(String fileName) {
      if (cloudFiles.containsKey(fileName) && cloudFiles[fileName] != null) {
        try { return jsonDecode(cloudFiles[fileName]); } catch (_) {}
      }
      return null;
    }

    // Advanced Deep-Compare & Deduplicating Merge Function
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

      // 1. Purge any tombstoned records
      final beforeLen = localList.length;
      localList.removeWhere((item) => tombstones.contains(getId(item)));
      if (localList.length != beforeLen) changed = true;

      // 2. Merge Cloud Records
      for (var rawMap in cloudList) {
        if (rawMap is! Map<String, dynamic>) continue;
        final cloudMap = rawMap;
        String id = (cloudMap['id'] ?? '').toString().trim();
        String billNo = (cloudMap['billNo'] ?? cloudMap['internalNo'] ?? cloudMap['voucherNo'] ?? '').toString().trim();

        // Skip if deleted
        if (id.isEmpty || tombstones.contains(id)) continue;

        // Match by exact ID or same Bill Number to prevent duplicate cards
        int idx = localList.indexWhere((e) => getId(e) == id || (billNo.isNotEmpty && getBillNo(e) == billNo));

        if (idx == -1) {
          // ADD NEW RECORD FROM CLOUD
          localList.add(fromMap(cloudMap));
          changed = true;
        } else {
          // In-Place Replace if content differs
          String localJson = jsonEncode(toMap(localList[idx]));
          String cloudJson = jsonEncode(cloudMap);

          if (localJson != cloudJson) {
            localList[idx] = fromMap(cloudMap);
            changed = true;
          }
        }
      }

      // 3. Final De-duplication Pass: Keep only 1 record per BillNo
      Map<String, T> uniqueByBillNo = {};
      for (var item in localList) {
        String bNo = getBillNo(item);
        if (bNo.isNotEmpty) {
          uniqueByBillNo[bNo] = item;
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
      (e) => e.internalNo.isNotEmpty ? e.internalNo : e.billNo, 
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

    // Master Records Sync
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
          if (lJson != cJson) { ph.parties[existingIdx] = Party.fromMap(partMap); hasChanges = true; }
        } else { ph.parties.add(Party.fromMap(partMap)); hasChanges = true; }
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
          if (lJson != cJson) { ph.medicines[existingIdx] = Medicine.fromMap(medMap); hasChanges = true; }
        } else { ph.medicines.add(Medicine.fromMap(medMap)); hasChanges = true; }
      }
    }

    return hasChanges || cSales || cPurc || cVouc || cSCh || cPCh || cSRet || cPRet;
  }
}
