// FILE: lib/web_live_sync/sync_protocol/delta_merge_engine.dart
import 'dart:convert';
import '../../../pharoah_manager.dart';
import '../../../models.dart';

class DeltaMergeEngine {
  /// Smartly merges cloud data. Accepts incoming edits from peer client atomically.
  static bool processCloudData(PharoahManager ph, Map<String, dynamic> cloudFiles, Set<String> tombstones, Map<String, String> localHashes) {
    bool hasChanges = false;

    dynamic decodeJson(String fileName) {
      if (cloudFiles.containsKey(fileName) && cloudFiles[fileName] != null) {
        try { return jsonDecode(cloudFiles[fileName]); } catch (_) {}
      }
      return null;
    }

    // Advanced Deep-Compare Merge Function
    bool mergeList<T>(
      List<dynamic>? cloudList,
      List<T> localList,
      String Function(T) getId,
      T Function(Map<String, dynamic>) fromMap,
      Map<String, dynamic> Function(T) toMap,
    ) {
      if (cloudList == null) return false;
      bool changed = false;

      for (var rawMap in cloudList) {
        final cloudMap = rawMap as Map<String, dynamic>;
        String id = cloudMap['id'] ?? '';
        
        // Skip if deleted
        if (id.isEmpty || tombstones.contains(id)) continue;

        int idx = localList.indexWhere((e) => getId(e) == id);
        
        if (idx == -1) {
          // ADD NEW RECORD FROM CLOUD
          localList.add(fromMap(cloudMap));
          changed = true;
        } else {
          // CONFLICT RESOLUTION: Check for modifications
          String localJson = jsonEncode(toMap(localList[idx]));
          String cloudJson = jsonEncode(cloudMap);
          
          if (localJson != cloudJson) {
            // ⚡ Cloud has newer modified transaction from peer client!
            // Update local memory with the peer's modification!
            localList[idx] = fromMap(cloudMap);
            changed = true;
          }
        }
      }
      return changed;
    }

    bool cSales = mergeList<Sale>(decodeJson('sales.json'), ph.sales, (e) => e.id, (m) => Sale.fromMap(m), (e) => e.toMap());
    bool cPurc  = mergeList<Purchase>(decodeJson('purc.json'), ph.purchases, (e) => e.id, (m) => Purchase.fromMap(m), (e) => e.toMap());
    bool cVouc  = mergeList<Voucher>(decodeJson('vouc.json'), ph.vouchers, (e) => e.id, (m) => Voucher.fromMap(m), (e) => e.toMap());
    bool cSCh   = mergeList<SaleChallan>(decodeJson('s_challan.json'), ph.saleChallans, (e) => e.id, (m) => SaleChallan.fromMap(m), (e) => e.toMap());
    bool cPCh   = mergeList<PurchaseChallan>(decodeJson('p_challan.json'), ph.purchaseChallans, (e) => e.id, (m) => PurchaseChallan.fromMap(m), (e) => e.toMap());
    bool cSRet  = mergeList<SaleReturn>(decodeJson('s_return.json'), ph.saleReturns, (e) => e.id, (m) => SaleReturn.fromMap(m), (e) => e.toMap());
    bool cPRet  = mergeList<PurchaseReturn>(decodeJson('p_return.json'), ph.purchaseReturns, (e) => e.id, (m) => PurchaseReturn.fromMap(m), (e) => e.toMap());

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
