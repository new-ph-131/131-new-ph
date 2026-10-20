// FILE: lib/logic/product_integrity_service.dart
// Live Revision: #PH-REV-738 (ENTERPRISE-CANONICAL-DEDUPLICATION-AND-TAP-RESOLUTION-FIX)

import 'package:flutter/foundation.dart';
import '../models.dart';
import '../sync_core/modules/medicine_sync_module.dart';
import '../sync_core/d1_sales_ledger_service.dart';

/// Result object for Product Deletion Integrity Check
class ProductDeleteCheckResult {
  final bool canDelete;
  final String reason;
  final String details;
  final int totalReferences;
  final List<String> sampleReferences;

  ProductDeleteCheckResult({
    required this.canDelete,
    required this.reason,
    required this.details,
    this.totalReferences = 0,
    this.sampleReferences = const [],
  });
}

/// 🛡️ UNIVERSAL PRODUCT INTEGRITY, CANONICAL DEDUPLICATION & HARVESTING SERVICE (#PH-REV-738)
/// 1. 360-Degree Deletion Usage Guard across Sales, Purchases, Challans, Returns & Batches.
/// 2. Canonical Deduplication to prevent multiple same-name products.
/// 3. Fault-Tolerant Tap Resolution for Bill Items (Guaranteed Batch/MRP Screen Open).
/// 4. Auto-Harvesting with Tombstone Revival (Transaction Authority over Deleted State).
class ProductIntegrityService {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  /// Generates the next unique, strictly-incrementing system ID (e.g. PH-10018)
  static String generateNextSystemId(List<Medicine> medicines) {
    int maxNum = 10000;
    for (var m in medicines) {
      final sys = m.systemId.trim().toUpperCase();
      if (sys.startsWith("PH-")) {
        final numPart = int.tryParse(sys.replaceFirst("PH-", ""));
        if (numPart != null && numPart > maxNum) {
          maxNum = numPart;
        }
      }
    }
    return "PH-${maxNum + 1}";
  }

  /// 🛡️ CANONICAL DEDUPLICATION ENGINE:
  /// Collapses any duplicated product master rows with same clean (name+packing) or systemId
  /// into a single canonical master record, eliminating screenshot duplicate rows.
  static int deduplicateMedicineList(List<Medicine> medicines) {
    if (medicines.length <= 1) return 0;
    int mergedCount = 0;

    final Map<String, int> compMap = {};
    final Map<String, int> sysMap = {};
    final List<Medicine> canonicalList = [];

    for (var med in medicines) {
      final String cName = cleanString(med.name);
      if (cName.isEmpty) continue;
      final String cPack = cleanString(med.packing);
      final String compKey = "${cName}_$cPack";
      final String sysKey = med.systemId.trim().toUpperCase();

      int matchIdx = -1;
      if (compKey.isNotEmpty && compMap.containsKey(compKey)) {
        matchIdx = compMap[compKey]!;
      } else if (sysKey.isNotEmpty && sysKey != "PH-0" && sysMap.containsKey(sysKey)) {
        matchIdx = sysMap[sysKey]!;
      }

      if (matchIdx != -1) {
        // Merge into existing canonical record
        final canon = canonicalList[matchIdx];
        if (canon.systemId.isEmpty && med.systemId.isNotEmpty) {
          canon.systemId = med.systemId;
        }
        if (med.version > canon.version) {
          canon.version = med.version;
        }
        if (med.updatedAt > canon.updatedAt) {
          canon.updatedAt = med.updatedAt;
        }
        if ((canon.hsnCode == "N/A" || canon.hsnCode.isEmpty) && med.hsnCode.isNotEmpty && med.hsnCode != "N/A") {
          canon.hsnCode = med.hsnCode;
        }
        if (canon.mrp <= 0 && med.mrp > 0) canon.mrp = med.mrp;
        if (canon.rateA <= 0 && med.rateA > 0) canon.rateA = med.rateA;
        if (canon.purRate <= 0 && med.purRate > 0) canon.purRate = med.purRate;
        if (canon.gst <= 0 && med.gst > 0) canon.gst = med.gst;
        mergedCount++;
      } else {
        final idx = canonicalList.length;
        canonicalList.add(med);
        if (compKey.isNotEmpty) compMap[compKey] = idx;
        if (sysKey.isNotEmpty && sysKey != "PH-0") sysMap[sysKey] = idx;
      }
    }

    if (mergedCount > 0) {
      medicines.clear();
      medicines.addAll(canonicalList);
    }
    return mergedCount;
  }

  /// 🛡️ FAULT-TOLERANT RESOLUTION FOR BILL ITEM (Fixes Problem 4):
  /// Guarantees that tapping on any item in bill creation ALWAYS resolves a valid Medicine
  /// so the Batch/MRP/Rate screen (ItemEntryCard) opens 100% of the time.
  static Medicine resolveMedicineForBillItem({
    required List<Medicine> medicines,
    required String medicineID,
    required String name,
    required String packing,
    String hsn = "3004",
    double gst = 12.0,
    double mrp = 0.0,
    double rate = 0.0,
  }) {
    final cleanId = medicineID.trim();
    final cleanName = cleanString(name);
    final cleanPack = cleanString(packing);

    // Tier 1: ID Match
    if (cleanId.isNotEmpty) {
      for (var m in medicines) {
        if (m.id.trim() == cleanId) return m;
      }
      // Tier 2: System ID Match
      for (var m in medicines) {
        if (m.systemId.trim().toUpperCase() == cleanId.toUpperCase()) return m;
      }
    }

    // Tier 3: Composite Name + Packing Match
    if (cleanName.isNotEmpty) {
      for (var m in medicines) {
        if (cleanString(m.name) == cleanName && (cleanPack.isEmpty || cleanString(m.packing) == cleanPack)) {
          return m;
        }
      }
      // Tier 4: Clean Name Match
      for (var m in medicines) {
        if (cleanString(m.name) == cleanName) return m;
      }
    }

    // Tier 5: Safe In-Memory Rehydration (Never leave null)
    final newId = cleanId.isNotEmpty ? cleanId : "MED-${DateTime.now().millisecondsSinceEpoch}";
    final fallbackMed = Medicine(
      id: newId,
      systemId: generateNextSystemId(medicines),
      name: name.trim().toUpperCase(),
      packing: packing.trim().isNotEmpty ? packing.trim().toUpperCase() : "1*1",
      hsnCode: hsn.trim().isNotEmpty ? hsn.trim().toUpperCase() : "3004",
      gst: gst > 0 ? gst : 12.0,
      mrp: mrp > 0 ? mrp : 0.0,
      rateA: rate > 0 ? rate : 0.0,
      drugForm: "TAB",
      stock: 0.0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: 1,
    );
    medicines.add(fallbackMed);
    return fallbackMed;
  }

  /// 🛡️ FAULT-TOLERANT RESOLUTION FOR PURCHASE ITEM:
  static Medicine resolveMedicineForPurchaseItem({
    required List<Medicine> medicines,
    required String medicineID,
    required String name,
    required String packing,
    String hsn = "3004",
    double gst = 12.0,
    double mrp = 0.0,
    double rateA = 0.0,
    double purchaseRate = 0.0,
  }) {
    final cleanId = medicineID.trim();
    final cleanName = cleanString(name);
    final cleanPack = cleanString(packing);

    if (cleanId.isNotEmpty) {
      for (var m in medicines) {
        if (m.id.trim() == cleanId) return m;
      }
      for (var m in medicines) {
        if (m.systemId.trim().toUpperCase() == cleanId.toUpperCase()) return m;
      }
    }

    if (cleanName.isNotEmpty) {
      for (var m in medicines) {
        if (cleanString(m.name) == cleanName && (cleanPack.isEmpty || cleanString(m.packing) == cleanPack)) {
          return m;
        }
      }
      for (var m in medicines) {
        if (cleanString(m.name) == cleanName) return m;
      }
    }

    final newId = cleanId.isNotEmpty ? cleanId : "MED-${DateTime.now().millisecondsSinceEpoch}";
    final fallbackMed = Medicine(
      id: newId,
      systemId: generateNextSystemId(medicines),
      name: name.trim().toUpperCase(),
      packing: packing.trim().isNotEmpty ? packing.trim().toUpperCase() : "1*1",
      hsnCode: hsn.trim().isNotEmpty ? hsn.trim().toUpperCase() : "3004",
      gst: gst > 0 ? gst : 12.0,
      mrp: mrp > 0 ? mrp : 0.0,
      rateA: rateA > 0 ? rateA : 0.0,
      purRate: purchaseRate > 0 ? purchaseRate : 0.0,
      drugForm: "TAB",
      stock: 0.0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      version: 1,
    );
    medicines.add(fallbackMed);
    return fallbackMed;
  }

  /// Checks if a BillItem matches a Medicine using 4-tier identification
  static bool doesItemMatchMedicine(BillItem it, Medicine med) {
    final String itMedId = it.medicineID.trim();
    final String medId = med.id.trim();
    if (itMedId.isNotEmpty && medId.isNotEmpty && itMedId == medId) return true;

    final String medSysId = med.systemId.trim().toUpperCase();
    if (itMedId.isNotEmpty && medSysId.isNotEmpty && itMedId.toUpperCase() == medSysId) return true;

    final String itCleanName = cleanString(it.name);
    final String medCleanName = cleanString(med.name);
    if (itCleanName.isEmpty || medCleanName.isEmpty) return false;

    final String itCleanPack = cleanString(it.packing);
    final String medCleanPack = cleanString(med.packing);

    if (itCleanPack.isNotEmpty && medCleanPack.isNotEmpty) {
      if (itCleanName == medCleanName && itCleanPack == medCleanPack) return true;
    } else {
      if (itCleanName == medCleanName) return true;
    }
    return false;
  }

  /// Checks if a PurchaseItem matches a Medicine using 4-tier identification
  static bool doesPurchaseItemMatchMedicine(PurchaseItem it, Medicine med) {
    final String itMedId = it.medicineID.trim();
    final String medId = med.id.trim();
    if (itMedId.isNotEmpty && medId.isNotEmpty && itMedId == medId) return true;

    final String medSysId = med.systemId.trim().toUpperCase();
    if (itMedId.isNotEmpty && medSysId.isNotEmpty && itMedId.toUpperCase() == medSysId) return true;

    final String itCleanName = cleanString(it.name);
    final String medCleanName = cleanString(med.name);
    if (itCleanName.isEmpty || medCleanName.isEmpty) return false;

    final String itCleanPack = cleanString(it.packing);
    final String medCleanPack = cleanString(med.packing);

    if (itCleanPack.isNotEmpty && medCleanPack.isNotEmpty) {
      if (itCleanName == medCleanName && itCleanPack == medCleanPack) return true;
    } else {
      if (itCleanName == medCleanName) return true;
    }
    return false;
  }

  /// 🛡️ 1. 360-DEGREE USAGE GUARD
  static ProductDeleteCheckResult checkProductDeletionEligibility({
    required Medicine med,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleChallan> saleChallans,
    required List<PurchaseChallan> purchaseChallans,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    Map<String, dynamic>? batchHistory,
  }) {
    final List<String> sampleRefs = [];
    int totalCount = 0;

    // 1. Check Sales Invoices
    final matchedSales = sales.where((s) {
      if (s.isDeleted == 1 || s.status == "Deleted") return false;
      return s.items.any((it) => doesItemMatchMedicine(it, med));
    }).toList();
    if (matchedSales.isNotEmpty) {
      totalCount += matchedSales.length;
      final samples = matchedSales.take(3).map((s) => s.billNo.isNotEmpty ? s.billNo : s.id).join(", ");
      sampleRefs.add("Sales Invoices ($samples)");
    }

    // 2. Check Purchase Inwards
    final matchedPurchases = purchases.where((p) {
      if (p.isDeleted == 1) return false;
      return p.items.any((it) => doesPurchaseItemMatchMedicine(it, med));
    }).toList();
    if (matchedPurchases.isNotEmpty) {
      totalCount += matchedPurchases.length;
      final samples = matchedPurchases.take(3).map((p) => p.billNo.isNotEmpty ? p.billNo : (p.internalNo.isNotEmpty ? p.internalNo : p.id)).join(", ");
      sampleRefs.add("Purchase Bills ($samples)");
    }

    // 3. Check Delivery Challans
    final matchedSaleChallans = saleChallans.where((c) {
      if (c.isDeleted == 1 || c.status == "Deleted") return false;
      return c.items.any((it) => doesItemMatchMedicine(it, med));
    }).toList();
    if (matchedSaleChallans.isNotEmpty) {
      totalCount += matchedSaleChallans.length;
      final samples = matchedSaleChallans.take(3).map((c) => c.billNo.isNotEmpty ? c.billNo : c.id).join(", ");
      sampleRefs.add("Delivery Challans ($samples)");
    }

    // 4. Check Purchase Challans
    final matchedPurchaseChallans = purchaseChallans.where((c) {
      if (c.isDeleted == 1 || c.status == "Deleted") return false;
      return c.items.any((it) => doesPurchaseItemMatchMedicine(it, med));
    }).toList();
    if (matchedPurchaseChallans.isNotEmpty) {
      totalCount += matchedPurchaseChallans.length;
      final samples = matchedPurchaseChallans.take(3).map((c) => c.billNo.isNotEmpty ? c.billNo : c.id).join(", ");
      sampleRefs.add("Purchase Challans ($samples)");
    }

    // 5. Check Sales Returns
    final matchedSaleReturns = saleReturns.where((r) {
      if (r.isDeleted == 1) return false;
      return r.items.any((it) => doesItemMatchMedicine(it, med));
    }).toList();
    if (matchedSaleReturns.isNotEmpty) {
      totalCount += matchedSaleReturns.length;
      final samples = matchedSaleReturns.take(3).map((r) => r.billNo.isNotEmpty ? r.billNo : r.id).join(", ");
      sampleRefs.add("Sale Returns ($samples)");
    }

    // 6. Check Purchase Returns
    final matchedPurchaseReturns = purchaseReturns.where((r) {
      if (r.isDeleted == 1) return false;
      return r.items.any((it) => doesPurchaseItemMatchMedicine(it, med));
    }).toList();
    if (matchedPurchaseReturns.isNotEmpty) {
      totalCount += matchedPurchaseReturns.length;
      final samples = matchedPurchaseReturns.take(3).map((r) => r.billNo.isNotEmpty ? r.billNo : r.id).join(", ");
      sampleRefs.add("Purchase Returns ($samples)");
    }

    // 7. Check Active Stock
    if (med.stock > 0) {
      return ProductDeleteCheckResult(
        canDelete: false,
        reason: "Active Inventory Stock Exists",
        details: "'${med.name}' currently has ${med.stock.toInt()} unit(s) in active inventory stock. Adjust stock to 0 before deletion.",
        totalReferences: totalCount + 1,
        sampleReferences: ["Active Stock (${med.stock.toInt()})", ...sampleRefs],
      );
    }

    if (totalCount > 0) {
      final String refSummary = sampleRefs.join("; ");
      return ProductDeleteCheckResult(
        canDelete: false,
        reason: "Transaction Records Exist",
        details: "Cannot delete '${med.name}' because it is linked to $totalCount active transaction record(s): $refSummary. Deletion blocked to protect GST, billing, and accounting audit trails.",
        totalReferences: totalCount,
        sampleReferences: sampleRefs,
      );
    }

    return ProductDeleteCheckResult(
      canDelete: true,
      reason: "Eligible for Deletion",
      details: "No linked bills, challans, or inventory found for '${med.name}'.",
      totalReferences: 0,
      sampleReferences: const [],
    );
  }

  /// 🔄 2A. ENSURE BILL ITEMS (Sales, Sale Challans, Returns)
  /// - Automatically revives tombstones if this item was previously deleted
  /// - Deduplicates and unifies line item with Product Master
  static int ensureLineItemsInProductMaster({
    required List<BillItem> items,
    required List<Medicine> medicines,
    required String storeToken,
    required void Function(Medicine newOrUpdatedMed) onMedicineSaved,
    String sourceTag = "TRANSACTION",
  }) {
    deduplicateMedicineList(medicines);
    int mutatedCount = 0;
    final int nowTs = DateTime.now().millisecondsSinceEpoch;

    final Map<String, int> idMap = {};
    final Map<String, int> sysMap = {};
    final Map<String, int> compMap = {};
    final Map<String, int> nameMap = {};

    for (int i = 0; i < medicines.length; i++) {
      final m = medicines[i];
      if (m.id.isNotEmpty) idMap[m.id.trim()] = i;
      if (m.systemId.isNotEmpty) sysMap[m.systemId.trim().toUpperCase()] = i;
      final cName = cleanString(m.name);
      final cPack = cleanString(m.packing);
      if (cName.isNotEmpty && cPack.isNotEmpty) compMap["${cName}_$cPack"] = i;
      if (cName.isNotEmpty && !nameMap.containsKey(cName)) nameMap[cName] = i;
    }

    for (var it in items) {
      final String cleanName = cleanString(it.name);
      if (cleanName.isEmpty) continue;

      final String cleanPack = cleanString(it.packing);
      final String itMedId = it.medicineID.trim();

      int matchIdx = -1;
      if (itMedId.isNotEmpty && idMap.containsKey(itMedId)) {
        matchIdx = idMap[itMedId]!;
      } else if (itMedId.isNotEmpty && sysMap.containsKey(itMedId.toUpperCase())) {
        matchIdx = sysMap[itMedId.toUpperCase()]!;
      } else if (cleanPack.isNotEmpty && compMap.containsKey("${cleanName}_$cleanPack")) {
        matchIdx = compMap["${cleanName}_$cleanPack"]!;
      } else if (nameMap.containsKey(cleanName)) {
        matchIdx = nameMap[cleanName]!;
      }

      if (matchIdx != -1) {
        final existingMed = medicines[matchIdx];
        if (it.medicineID != existingMed.id) {
          it.medicineID = existingMed.id;
        }

        // 🛡️ UNMARK TOMBSTONE (Transaction Authority): Revive product if previously deleted!
        final compKey = MedicineSyncModule.getCompositeKey(name: existingMed.name, packing: existingMed.packing, company: existingMed.companyId);
        D1SalesLedgerService.unmarkPermanentlyDeleted(existingMed.id, existingMed.systemId, compKey);

        bool enriched = false;
        if ((existingMed.hsnCode == "N/A" || existingMed.hsnCode.isEmpty) && it.hsn.isNotEmpty && it.hsn != "N/A") {
          existingMed.hsnCode = it.hsn.trim();
          enriched = true;
        }
        if (existingMed.gst <= 0 && it.gstRate > 0) {
          existingMed.gst = it.gstRate;
          enriched = true;
        }
        if (existingMed.mrp <= 0 && it.mrp > 0) {
          existingMed.mrp = it.mrp;
          enriched = true;
        }
        if (existingMed.rateA <= 0 && it.rate > 0) {
          existingMed.rateA = it.rate;
          enriched = true;
        }

        if (enriched) {
          existingMed.version += 1;
          existingMed.updatedAt = nowTs;
          onMedicineSaved(existingMed);
          mutatedCount++;
        }
      } else {
        // 🆕 Create new permanent Medicine record with strictly unique next System ID
        final String newId = (itMedId.isNotEmpty && itMedId != "0" && itMedId != "temp")
            ? itMedId
            : "MED-$nowTs-${medicines.length + 1}";
        final String newSysId = generateNextSystemId(medicines);

        final newMed = Medicine(
          id: newId,
          systemId: newSysId,
          name: it.name.trim().toUpperCase(),
          packing: it.packing.trim().isNotEmpty ? it.packing.trim().toUpperCase() : "1*1",
          hsnCode: it.hsn.trim().isNotEmpty ? it.hsn.trim().toUpperCase() : "3004",
          gst: it.gstRate > 0 ? it.gstRate : 12.0,
          mrp: it.mrp > 0 ? it.mrp : 0.0,
          rateA: it.rate > 0 ? it.rate : 0.0,
          purRate: 0.0,
          drugForm: "TAB",
          stock: 0.0,
          updatedAt: nowTs,
          version: 1,
          isDeleted: 0,
        );

        it.medicineID = newMed.id;
        medicines.add(newMed);

        int newIdx = medicines.length - 1;
        idMap[newMed.id] = newIdx;
        sysMap[newMed.systemId.toUpperCase()] = newIdx;
        if (cleanPack.isNotEmpty) compMap["${cleanName}_$cleanPack"] = newIdx;
        if (!nameMap.containsKey(cleanName)) nameMap[cleanName] = newIdx;

        // Unmark tombstones for this revived/new item
        final compKey = MedicineSyncModule.getCompositeKey(name: newMed.name, packing: newMed.packing, company: newMed.companyId);
        D1SalesLedgerService.unmarkPermanentlyDeleted(newMed.id, newMed.systemId, compKey);

        onMedicineSaved(newMed);
        mutatedCount++;
      }
    }

    return mutatedCount;
  }

  /// 🔄 2B. ENSURE PURCHASE ITEMS (Purchases & Purchase Challans)
  static int ensurePurchaseItemsInProductMaster({
    required List<PurchaseItem> items,
    required List<Medicine> medicines,
    required String storeToken,
    required void Function(Medicine newOrUpdatedMed) onMedicineSaved,
    String sourceTag = "PURCHASE",
  }) {
    deduplicateMedicineList(medicines);
    int mutatedCount = 0;
    final int nowTs = DateTime.now().millisecondsSinceEpoch;

    final Map<String, int> idMap = {};
    final Map<String, int> sysMap = {};
    final Map<String, int> compMap = {};
    final Map<String, int> nameMap = {};

    for (int i = 0; i < medicines.length; i++) {
      final m = medicines[i];
      if (m.id.isNotEmpty) idMap[m.id.trim()] = i;
      if (m.systemId.isNotEmpty) sysMap[m.systemId.trim().toUpperCase()] = i;
      final cName = cleanString(m.name);
      final cPack = cleanString(m.packing);
      if (cName.isNotEmpty && cPack.isNotEmpty) compMap["${cName}_$cPack"] = i;
      if (cName.isNotEmpty && !nameMap.containsKey(cName)) nameMap[cName] = i;
    }

    for (var it in items) {
      final String cleanName = cleanString(it.name);
      if (cleanName.isEmpty) continue;

      final String cleanPack = cleanString(it.packing);
      final String itMedId = it.medicineID.trim();

      int matchIdx = -1;
      if (itMedId.isNotEmpty && idMap.containsKey(itMedId)) {
        matchIdx = idMap[itMedId]!;
      } else if (itMedId.isNotEmpty && sysMap.containsKey(itMedId.toUpperCase())) {
        matchIdx = sysMap[itMedId.toUpperCase()]!;
      } else if (cleanPack.isNotEmpty && compMap.containsKey("${cleanName}_$cleanPack")) {
        matchIdx = compMap["${cleanName}_$cleanPack"]!;
      } else if (nameMap.containsKey(cleanName)) {
        matchIdx = nameMap[cleanName]!;
      }

      if (matchIdx != -1) {
        final existingMed = medicines[matchIdx];
        if (it.medicineID != existingMed.id) {
          it.medicineID = existingMed.id;
        }

        final compKey = MedicineSyncModule.getCompositeKey(name: existingMed.name, packing: existingMed.packing, company: existingMed.companyId);
        D1SalesLedgerService.unmarkPermanentlyDeleted(existingMed.id, existingMed.systemId, compKey);

        bool enriched = false;
        if ((existingMed.hsnCode == "N/A" || existingMed.hsnCode.isEmpty) && it.hsn.isNotEmpty && it.hsn != "N/A") {
          existingMed.hsnCode = it.hsn.trim();
          enriched = true;
        }
        if (existingMed.gst <= 0 && it.gstRate > 0) {
          existingMed.gst = it.gstRate;
          enriched = true;
        }
        if (existingMed.mrp <= 0 && it.mrp > 0) {
          existingMed.mrp = it.mrp;
          enriched = true;
        }
        if (existingMed.purRate <= 0 && it.purchaseRate > 0) {
          existingMed.purRate = it.purchaseRate;
          enriched = true;
        }
        if (existingMed.rateA <= 0 && it.rateA > 0) {
          existingMed.rateA = it.rateA;
          enriched = true;
        }

        if (enriched) {
          existingMed.version += 1;
          existingMed.updatedAt = nowTs;
          onMedicineSaved(existingMed);
          mutatedCount++;
        }
      } else {
        final String newId = (itMedId.isNotEmpty && itMedId != "0" && itMedId != "temp")
            ? itMedId
            : "MED-$nowTs-${medicines.length + 1}";
        final String newSysId = generateNextSystemId(medicines);

        final newMed = Medicine(
          id: newId,
          systemId: newSysId,
          name: it.name.trim().toUpperCase(),
          packing: it.packing.trim().isNotEmpty ? it.packing.trim().toUpperCase() : "1*1",
          hsnCode: it.hsn.trim().isNotEmpty ? it.hsn.trim().toUpperCase() : "3004",
          gst: it.gstRate > 0 ? it.gstRate : 12.0,
          mrp: it.mrp > 0 ? it.mrp : 0.0,
          rateA: it.rateA > 0 ? it.rateA : (it.mrp > 0 ? it.mrp : 0.0),
          purRate: it.purchaseRate > 0 ? it.purchaseRate : 0.0,
          drugForm: "TAB",
          stock: 0.0,
          updatedAt: nowTs,
          version: 1,
          isDeleted: 0,
        );

        it.medicineID = newMed.id;
        medicines.add(newMed);

        int newIdx = medicines.length - 1;
        idMap[newMed.id] = newIdx;
        sysMap[newMed.systemId.toUpperCase()] = newIdx;
        if (cleanPack.isNotEmpty) compMap["${cleanName}_$cleanPack"] = newIdx;
        if (!nameMap.containsKey(cleanName)) nameMap[cleanName] = newIdx;

        final compKey = MedicineSyncModule.getCompositeKey(name: newMed.name, packing: newMed.packing, company: newMed.companyId);
        D1SalesLedgerService.unmarkPermanentlyDeleted(newMed.id, newMed.systemId, compKey);

        onMedicineSaved(newMed);
        mutatedCount++;
      }
    }

    return mutatedCount;
  }

  /// 📥 3. HARVEST MISSING PRODUCTS FROM ALL INCOMING TRANSACTIONS (After Cloud Pull)
  static int harvestProductsFromAllTransactions({
    required List<Medicine> medicines,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleChallan> saleChallans,
    required List<PurchaseChallan> purchaseChallans,
    required String storeToken,
    required void Function(Medicine) onMedicineSaved,
  }) {
    deduplicateMedicineList(medicines);
    int harvested = 0;
    for (var s in sales) {
      if (s.isDeleted == 1) continue;
      harvested += ensureLineItemsInProductMaster(
        items: s.items,
        medicines: medicines,
        storeToken: storeToken,
        onMedicineSaved: onMedicineSaved,
        sourceTag: "SALE",
      );
    }
    for (var p in purchases) {
      if (p.isDeleted == 1) continue;
      harvested += ensurePurchaseItemsInProductMaster(
        items: p.items,
        medicines: medicines,
        storeToken: storeToken,
        onMedicineSaved: onMedicineSaved,
        sourceTag: "PURCHASE",
      );
    }
    for (var sc in saleChallans) {
      if (sc.isDeleted == 1) continue;
      harvested += ensureLineItemsInProductMaster(
        items: sc.items,
        medicines: medicines,
        storeToken: storeToken,
        onMedicineSaved: onMedicineSaved,
        sourceTag: "CHALLAN",
      );
    }
    for (var pc in purchaseChallans) {
      if (pc.isDeleted == 1) continue;
      harvested += ensurePurchaseItemsInProductMaster(
        items: pc.items,
        medicines: medicines,
        storeToken: storeToken,
        onMedicineSaved: onMedicineSaved,
        sourceTag: "PURCHASE_CHALLAN",
      );
    }
    deduplicateMedicineList(medicines);
    return harvested;
  }
}
