// FILE: lib/logic/master_cascade_service.dart
// Live Revision: #PH-REV-739 (ENTERPRISE-UNIVERSAL-MASTER-CASCADE-AND-DYNAMIC-PRINT-RESOLUTION)

import 'package:flutter/foundation.dart';
import '../models.dart';
import 'product_integrity_service.dart';
import '../sync_core/modules/party_sync_module.dart';

/// 🛡️ DYNAMIC MASTER ENTITY RESOLVER
/// Used across all UI Views and all PDF Print Generators (Sales, Purchases, Challans, Returns, Vouchers, Ledgers).
/// Guarantees that whenever an invoice or report is viewed or printed, it dynamically reflects
/// the latest Master Description (Name, Packing, HSN, Address, GSTIN, Phone, DL) even for old transactions.
class MasterEntityResolver {
  static String clean(String s) => ProductIntegrityService.cleanString(s);

  /// Resolves the latest Medicine object from Product Master using 4-tier match
  static Medicine? findMedicine(List<Medicine> medicines, String medId, String itemName, [String itemPacking = ""]) {
    final cleanId = medId.trim();
    final cleanName = clean(itemName);
    final cleanPack = clean(itemPacking);

    if (cleanId.isNotEmpty) {
      for (final m in medicines) {
        if (m.id == cleanId) return m;
      }
      for (final m in medicines) {
        if (m.systemId.trim().toUpperCase() == cleanId.toUpperCase()) return m;
      }
    }

    if (cleanName.isNotEmpty) {
      if (cleanPack.isNotEmpty) {
        for (final m in medicines) {
          if (clean(m.name) == cleanName && clean(m.packing) == cleanPack) return m;
        }
      }
      for (final m in medicines) {
        if (clean(m.name) == cleanName) return m;
      }
    }
    return null;
  }

  /// Resolves the latest Party object from Party Master
  static Party? findParty(List<Party> parties, String partyId, [String fallbackName = ""]) {
    final cleanId = partyId.trim();
    final cleanName = PartySyncModule.cleanString(fallbackName);

    if (cleanId.isNotEmpty) {
      for (final p in parties) {
        if (p.id == cleanId) return p;
      }
    }

    if (cleanName.isNotEmpty) {
      for (final p in parties) {
        if (PartySyncModule.cleanString(p.name) == cleanName) return p;
      }
    }
    return null;
  }

  static String resolveItemName(BillItem it, List<Medicine> medicines) {
    final med = findMedicine(medicines, it.medicineID, it.name, it.packing);
    return (med != null && med.name.trim().isNotEmpty) ? med.name.trim() : it.name;
  }

  static String resolveItemPacking(BillItem it, List<Medicine> medicines) {
    final med = findMedicine(medicines, it.medicineID, it.name, it.packing);
    return (med != null && med.packing.trim().isNotEmpty) ? med.packing.trim() : it.packing;
  }

  static String resolveItemHsn(BillItem it, List<Medicine> medicines) {
    final med = findMedicine(medicines, it.medicineID, it.name, it.packing);
    return (med != null && med.hsnCode.trim().isNotEmpty && med.hsnCode != "N/A") ? med.hsnCode.trim() : it.hsn;
  }

  static String resolvePurchaseItemName(PurchaseItem it, List<Medicine> medicines) {
    final med = findMedicine(medicines, it.medicineID, it.name, it.packing);
    return (med != null && med.name.trim().isNotEmpty) ? med.name.trim() : it.name;
  }

  static String resolvePurchaseItemPacking(PurchaseItem it, List<Medicine> medicines) {
    final med = findMedicine(medicines, it.medicineID, it.name, it.packing);
    return (med != null && med.packing.trim().isNotEmpty) ? med.packing.trim() : it.packing;
  }

  static String resolvePurchaseItemHsn(PurchaseItem it, List<Medicine> medicines) {
    final med = findMedicine(medicines, it.medicineID, it.name, it.packing);
    return (med != null && med.hsnCode.trim().isNotEmpty && med.hsnCode != "N/A") ? med.hsnCode.trim() : it.hsn;
  }
}

/// 🛡️ UNIVERSAL MASTER CASCADE SERVICE (#PH-REV-739)
/// Propagates Master Data Updates (Name, Packing, HSN, Party Details) to all active & historical transactions.
/// Protects financial calculations (Rate, GST %, Net Amount, Totals) while keeping descriptive metadata 100% synchronized!
class MasterCascadeService {
  static String clean(String s) => ProductIntegrityService.cleanString(s);

  /// 🔄 1. CASCADE PRODUCT MASTER UPDATES TO ALL TRANSACTION LINE ITEMS
  static int cascadeProductUpdate({
    required Medicine updatedMed,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleChallan> saleChallans,
    required List<PurchaseChallan> purchaseChallans,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
  }) {
    int mutatedItems = 0;
    final cleanMedId = updatedMed.id.trim();
    final cleanMedSysId = updatedMed.systemId.trim().toUpperCase();
    final cleanMedName = clean(updatedMed.name);
    final cleanMedPack = clean(updatedMed.packing);

    bool matchesItem(String itMedId, String itName, String itPack) {
      if (cleanMedId.isNotEmpty && itMedId.trim() == cleanMedId) return true;
      if (cleanMedSysId.isNotEmpty && itMedId.trim().toUpperCase() == cleanMedSysId) return true;
      final cName = clean(itName);
      final cPack = clean(itPack);
      if (cName.isNotEmpty && cName == cleanMedName) {
        if (cleanMedPack.isNotEmpty && cPack.isNotEmpty) {
          return cPack == cleanMedPack;
        }
        return true;
      }
      return false;
    }

    // A. Sales Invoices
    for (var s in sales) {
      bool billMutated = false;
      for (var it in s.items) {
        if (matchesItem(it.medicineID, it.name, it.packing)) {
          it.name = updatedMed.name.trim();
          it.packing = updatedMed.packing.trim();
          if (updatedMed.hsnCode.isNotEmpty && updatedMed.hsnCode != "N/A") {
            it.hsn = updatedMed.hsnCode.trim();
          }
          it.medicineID = updatedMed.id;
          billMutated = true;
          mutatedItems++;
        }
      }
      if (billMutated) s.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }

    // B. Purchase Inward Bills
    for (var p in purchases) {
      bool billMutated = false;
      for (var it in p.items) {
        if (matchesItem(it.medicineID, it.name, it.packing)) {
          it.name = updatedMed.name.trim();
          it.packing = updatedMed.packing.trim();
          if (updatedMed.hsnCode.isNotEmpty && updatedMed.hsnCode != "N/A") {
            it.hsn = updatedMed.hsnCode.trim();
          }
          it.medicineID = updatedMed.id;
          billMutated = true;
          mutatedItems++;
        }
      }
      if (billMutated) p.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }

    // C. Sale Delivery Challans
    for (var sc in saleChallans) {
      bool billMutated = false;
      for (var it in sc.items) {
        if (matchesItem(it.medicineID, it.name, it.packing)) {
          it.name = updatedMed.name.trim();
          it.packing = updatedMed.packing.trim();
          if (updatedMed.hsnCode.isNotEmpty && updatedMed.hsnCode != "N/A") {
            it.hsn = updatedMed.hsnCode.trim();
          }
          it.medicineID = updatedMed.id;
          billMutated = true;
          mutatedItems++;
        }
      }
      if (billMutated) sc.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }

    // D. Purchase Challans
    for (var pc in purchaseChallans) {
      bool billMutated = false;
      for (var it in pc.items) {
        if (matchesItem(it.medicineID, it.name, it.packing)) {
          it.name = updatedMed.name.trim();
          it.packing = updatedMed.packing.trim();
          if (updatedMed.hsnCode.isNotEmpty && updatedMed.hsnCode != "N/A") {
            it.hsn = updatedMed.hsnCode.trim();
          }
          it.medicineID = updatedMed.id;
          billMutated = true;
          mutatedItems++;
        }
      }
      if (billMutated) pc.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }

    // E. Sale Returns (Credit Notes)
    for (var sr in saleReturns) {
      for (var it in sr.items) {
        if (matchesItem(it.medicineID, it.name, it.packing)) {
          it.name = updatedMed.name.trim();
          it.packing = updatedMed.packing.trim();
          if (updatedMed.hsnCode.isNotEmpty && updatedMed.hsnCode != "N/A") {
            it.hsn = updatedMed.hsnCode.trim();
          }
          it.medicineID = updatedMed.id;
          mutatedItems++;
        }
      }
    }

    // F. Purchase Returns (Debit Notes)
    for (var pr in purchaseReturns) {
      for (var it in pr.items) {
        if (matchesItem(it.medicineID, it.name, it.packing)) {
          it.name = updatedMed.name.trim();
          it.packing = updatedMed.packing.trim();
          if (updatedMed.hsnCode.isNotEmpty && updatedMed.hsnCode != "N/A") {
            it.hsn = updatedMed.hsnCode.trim();
          }
          it.medicineID = updatedMed.id;
          mutatedItems++;
        }
      }
    }

    return mutatedItems;
  }

  /// 🔄 2. CASCADE PARTY MASTER UPDATES TO ALL TRANSACTIONS & VOUCHERS
  static int cascadePartyUpdate({
    required Party updatedParty,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<SaleChallan> saleChallans,
    required List<PurchaseChallan> purchaseChallans,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
    required List<Voucher> vouchers,
  }) {
    int mutatedRecords = 0;
    final cleanPartyId = updatedParty.id.trim();
    final cleanPartyName = PartySyncModule.cleanString(updatedParty.name);

    bool matchesParty(String id, String name) {
      if (cleanPartyId.isNotEmpty && id.trim() == cleanPartyId) return true;
      if (cleanPartyName.isNotEmpty && PartySyncModule.cleanString(name) == cleanPartyName) return true;
      return false;
    }

    // A. Sales
    for (var s in sales) {
      if (matchesParty(s.partyId, s.partyName)) {
        s.partyName = updatedParty.name;
        s.partyAddress = updatedParty.address;
        s.partyCity = updatedParty.city;
        s.partyGstin = updatedParty.gst;
        s.partyDl = updatedParty.dl;
        s.partyPhone = updatedParty.phone;
        s.partyEmail = updatedParty.email;
        s.partyState = updatedParty.state;
        s.partyId = updatedParty.id;
        s.updatedAt = DateTime.now().millisecondsSinceEpoch;
        mutatedRecords++;
      }
    }

    // B. Purchases
    for (var p in purchases) {
      if (matchesParty(p.partyId, p.distributorName)) {
        p.distributorName = updatedParty.name;
        p.partyId = updatedParty.id;
        p.updatedAt = DateTime.now().millisecondsSinceEpoch;
        mutatedRecords++;
      }
    }

    // C. Sale Challans
    for (var sc in saleChallans) {
      if (matchesParty(sc.partyId, sc.partyName)) {
        sc.partyName = updatedParty.name;
        sc.partyAddress = updatedParty.address;
        sc.partyCity = updatedParty.city;
        sc.partyGstin = updatedParty.gst;
        sc.partyDl = updatedParty.dl;
        sc.partyPhone = updatedParty.phone;
        sc.partyEmail = updatedParty.email;
        sc.partyState = updatedParty.state;
        sc.partyId = updatedParty.id;
        sc.updatedAt = DateTime.now().millisecondsSinceEpoch;
        mutatedRecords++;
      }
    }

    // D. Purchase Challans
    for (var pc in purchaseChallans) {
      if (matchesParty(pc.partyId, pc.distributorName)) {
        pc.distributorName = updatedParty.name;
        pc.partyId = updatedParty.id;
        pc.updatedAt = DateTime.now().millisecondsSinceEpoch;
        mutatedRecords++;
      }
    }

    // E. Sale Returns (Credit Notes)
    for (var sr in saleReturns) {
      if (matchesParty(sr.partyId, sr.partyName)) {
        sr.partyName = updatedParty.name;
        sr.partyAddress = updatedParty.address;
        sr.partyGstin = updatedParty.gst;
        sr.partyPhone = updatedParty.phone;
        sr.partyId = updatedParty.id;
        mutatedRecords++;
      }
    }

    // F. Purchase Returns (Debit Notes)
    for (var pr in purchaseReturns) {
      if (matchesParty(pr.partyId, pr.distributorName)) {
        pr.distributorName = updatedParty.name;
        pr.partyId = updatedParty.id;
        mutatedRecords++;
      }
    }

    // G. Vouchers & Ledger Receipts
    for (var v in vouchers) {
      if (matchesParty(v.partyId, v.partyName)) {
        v.partyName = updatedParty.name;
        v.partyId = updatedParty.id;
        v.updatedAt = DateTime.now().millisecondsSinceEpoch;
        mutatedRecords++;
      }
    }

    return mutatedRecords;
  }
}
