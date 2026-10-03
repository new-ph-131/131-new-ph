// FILE: lib/web_live_sync/sync_protocol/delta_merge_engine.dart

import 'dart:convert';
import '../../../pharoah_manager.dart';
import '../../../models.dart';

class DeltaMergeEngine {
  /// Smartly merges cloud data. If a record exists locally but was modified on the web, it overwrites it.
  static bool processCloudData(PharoahManager ph, Map<String, dynamic> cloudFiles, Set<String> tombstones) {
    bool hasChanges = false;

    dynamic decodeJson(String fileName) {
      if (cloudFiles.containsKey(fileName) && cloudFiles[fileName] != null) {
        try { return jsonDecode(cloudFiles[fileName]); } catch (_) {}
      }
      return null;
    }

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
        
        if (id.isEmpty || tombstones.contains(id)) continue;

        int idx = localList.indexWhere((e) => getId(e) == id);
        
        if (idx == -1) {
          localList.add(fromMap(cloudMap));
          changed = true;
        } else {
          String localJson = jsonEncode(toMap(localList[idx]));
          String cloudJson = jsonEncode(cloudMap);
          if (localJson != cloudJson) {
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

    // Party Deduplication Merge Logic
    var rawParts = decodeJson('parts.json') as List?;
    if (rawParts != null) {
      for (var rawPart in rawParts) {
        final partMap = rawPart as Map<String, dynamic>;
        String cleanName = (partMap['name'] ?? '').toString().replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        String pGst = (partMap['gst'] ?? '').toString().toUpperCase().trim();
        if (cleanName.isEmpty) continue;

        int existingIdx = ph.parties.indexWhere((p) {
          if (pGst.isNotEmpty && pGst != 'N/A' && p.gst.toUpperCase().trim() == pGst) return true;
          return p.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase() == cleanName;
        });

        if (existingIdx != -1) {
          final oldP = ph.parties[existingIdx];
          final incoming = Party.fromMap(partMap);
          ph.parties[existingIdx] = Party(
            id: oldP.id, name: oldP.name, group: incoming.group,
            phone: incoming.phone.isNotEmpty ? incoming.phone : oldP.phone,
            email: incoming.email.isNotEmpty ? incoming.email : oldP.email,
            address: incoming.address.isNotEmpty ? incoming.address : oldP.address,
            city: incoming.city.isNotEmpty ? incoming.city : oldP.city,
            state: incoming.state,
            gst: incoming.gst.isNotEmpty && incoming.gst != 'N/A' ? incoming.gst : oldP.gst,
            dl: incoming.dl.isNotEmpty && incoming.dl != 'N/A' ? incoming.dl : oldP.dl,
            pan: incoming.pan.isNotEmpty ? incoming.pan : oldP.pan,
            opBal: incoming.opBal != 0.0 ? incoming.opBal : oldP.opBal,
          );
        } else {
          ph.parties.add(Party.fromMap(partMap));
          hasChanges = true;
        }
      }
    }

    // Medicine Deduplication Merge Logic
    var rawMeds = decodeJson('meds.json') as List?;
    if (rawMeds != null) {
      for (var rawMed in rawMeds) {
        final medMap = rawMed as Map<String, dynamic>;
        String cleanName = (medMap['name'] ?? '').toString().replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        if (cleanName.isEmpty) continue;

        int existingIdx = ph.medicines.indexWhere((m) {
          return m.name.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase() == cleanName;
        });

        if (existingIdx != -1) {
          final oldM = ph.medicines[existingIdx];
          final incoming = Medicine.fromMap(medMap);
          ph.medicines[existingIdx] = Medicine(
            id: oldM.id,
            systemId: oldM.systemId.isNotEmpty ? oldM.systemId : incoming.systemId,
            name: oldM.name,
            packing: incoming.packing.isNotEmpty ? incoming.packing : oldM.packing,
            companyId: incoming.companyId.isNotEmpty ? incoming.companyId : oldM.companyId,
            saltId: incoming.saltId.isNotEmpty ? incoming.saltId : oldM.saltId,
            hsnCode: incoming.hsnCode.isNotEmpty ? incoming.hsnCode : oldM.hsnCode,
            gst: incoming.gst,
            mrp: incoming.mrp > 0 ? incoming.mrp : oldM.mrp,
            purRate: incoming.purRate > 0 ? incoming.purRate : oldM.purRate,
            rateA: incoming.rateA > 0 ? incoming.rateA : oldM.rateA,
            rateB: incoming.rateB > 0 ? incoming.rateB : oldM.rateB,
            rateC: incoming.rateC > 0 ? incoming.rateC : oldM.rateC,
            stock: oldM.stock > 0 ? oldM.stock : incoming.stock,
            drugForm: incoming.drugForm,
          );
        } else {
          ph.medicines.add(Medicine.fromMap(medMap));
          hasChanges = true;
        }
      }
    }

    return hasChanges || cSales || cPurc || cVouc || cSCh || cPCh || cSRet || cPRet;
  }
}
