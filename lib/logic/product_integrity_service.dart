// FILE: lib/logic/product_integrity_service.dart
// Live Revision: #PH-REV-737 (UNIVERSAL-PRODUCT-INTEGRITY-AND-USAGE-GUARD-FIX)

import 'package:flutter/foundation.dart';
import '../models.dart';
import '../sync_core/modules/medicine_sync_module.dart';

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

/// 🛡️ UNIVERSAL PRODUCT INTEGRITY & HARVESTING SERVICE (#PH-REV-737)
/// 1. 360-Degree Deletion Usage Guard across Sales, Purchases, Challans, Returns & Batches.
/// 2. Universal Auto-Harvesting & Auto-Upsert to ensure line items in any bill,
///    challan, CSV import, or sync packet automatically link and update Product Master.
class ProductIntegrityService {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  /// Checks if a BillItem matches a Medicine using 4-tier identification
  static bool doesItemMatchMedicine(BillItem it, Medicine med) {
    final String itMedId = it.medicineID.trim();
    final String medId = med.id.trim();
    if (itMedId.isNotEmpty && medId.isNotEmpty && itMedId == medId) {
      return true;
    }

    final String medSysId = med.systemId.trim().toUpperCase();
    if (itMedId.isNotEmpty && medSysId.isNotEmpty && itMedId.toUpperCase() == medSysId) {
      return true;
    }

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
    if (itMedId.isNotEmpty && medId.isNotEmpty && itMedId == medId) {
      return true;
    }

    final String medSysId = med.systemId.trim().toUpperCase();
    if (itMedId.isNotEmpty && medSysId.isNotEmpty && itMedId.toUpperCase() == medSysId) {
      return true;
    }

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

  /// 🛡️ 1. 360-DEGREE USAGE GUARD: Checks all transactions across both App & Web
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

    // 1. Check Sales Invoices (Active & non-deleted)
    final matchedSales = sales.where((s) {
      if (s.isDeleted == 1 || s.status == "Deleted") return false;
      return s.items.any((it) => doesItemMatchMedicine(it, med));
    }).toList();
    if (matchedSales.isNotEmpty) {
      totalCount += matchedSales.length;
      final samples = matchedSales.take(3).map((s) => s.billNo.isNotEmpty ? s.billNo : s.id).join(", ");
      sampleRefs.add("Sales Invoices ($samples)");
    }

    // 2. Check Purchase Inwards (Active & non-deleted)
    final matchedPurchases = purchases.where((p) {
      if (p.isDeleted == 1 || p.status == "Deleted") return false;
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

    // 5. Check Sales Returns / Credit Notes
    final matchedSaleReturns = saleReturns.where((r) {
      if (r.isDeleted == 1) return false;
      return r.items.any((it) => doesItemMatchMedicine(it, med));
    }).toList();
    if (matchedSaleReturns.isNotEmpty) {
      totalCount += matchedSaleReturns.length;
      final samples = matchedSaleReturns.take(3).map((r) => r.billNo.isNotEmpty ? r.billNo : r.id).join(", ");
      sampleRefs.add("Sale Returns ($samples)");
    }

    // 6. Check Purchase Returns / Debit Notes
    final matchedPurchaseReturns = purchaseReturns.where((r) {
      if (r.isDeleted == 1) return false;
      return r.items.any((it) => doesItemMatchMedicine(it, med));
    }).toList();
    if (matchedPurchaseReturns.isNotEmpty) {
      totalCount += matchedPurchaseReturns.length;
      final samples = matchedPurchaseReturns.take(3).map((r) => r.billNo.isNotEmpty ? r.billNo : r.id).join(", ");
      sampleRefs.add("Purchase Returns ($samples)");
    }

    // 7. Check Active Stock in Master
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
  static int ensureLineItemsInProductMaster({
    required List<BillItem> items,
    required List<Medicine> medicines,
    required String storeToken,
    required void Function(Medicine newOrUpdatedMed) onMedicineSaved,
    String sourceTag = "TRANSACTION",
  }) {
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
      if (cName.isNotEmpty && cPack.isNotEmpty) {
        compMap["${cName}_$cPack"] = i;
      }
      if (cName.isNotEmpty && !nameMap.containsKey(cName)) {
        nameMap[cName] = i;
      }
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
        final String newId = (itMedId.isNotEmpty && itMedId != "0" && itMedId != "temp")
            ? itMedId
            : "MED-$nowTs-${medicines.length + 1}";
        final String newSysId = "PH-${10000 + medicines.length + 1}";

        final newMed = Medicine(
          id: newId,
          systemId: newSysId,
          name: it.name.trim(),
          packing: it.packing.trim().isNotEmpty ? it.packing.trim() : "1*1",
          hsnCode: it.hsn.trim().isNotEmpty ? it.hsn.trim() : "N/A",
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
      if (cName.isNotEmpty && cPack.isNotEmpty) {
        compMap["${cName}_$cPack"] = i;
      }
      if (cName.isNotEmpty && !nameMap.containsKey(cName)) {
        nameMap[cName] = i;
      }
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
        final String newSysId = "PH-${10000 + medicines.length + 1}";

        final newMed = Medicine(
          id: newId,
          systemId: newSysId,
          name: it.name.trim(),
          packing: it.packing.trim().isNotEmpty ? it.packing.trim() : "1*1",
          hsnCode: it.hsn.trim().isNotEmpty ? it.hsn.trim() : "N/A",
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
    return harvested;
  }
}
