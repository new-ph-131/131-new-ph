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
        sc.partyGstin = updatedParty.gst;
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
      if (cleanPartyName.isNotEmpty && PartySyncModule.cleanString(sr.partyName) == cleanPartyName) {
        sr.partyName = updatedParty.name;
        sr.updatedAt = DateTime.now().millisecondsSinceEpoch;
        mutatedRecords++;
      }
    }

    // F. Purchase Returns (Debit Notes)
    for (var pr in purchaseReturns) {
      if (cleanPartyName.isNotEmpty && PartySyncModule.cleanString(pr.distributorName) == cleanPartyName) {
        pr.distributorName = updatedParty.name;
        pr.updatedAt = DateTime.now().millisecondsSinceEpoch;
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

  /// 🔄 3. CASCADE COMPANY / BRAND MASTER UPDATES TO PRODUCTS & SHORTAGES (#PH-REV-768)
  /// Ensures renaming e.g. CIPLA -> PIPLA automatically updates all linked products & shortages everywhere!
  static int cascadeCompanyUpdate({
    required Company updatedCompany,
    String? previousName,
    required List<Medicine> medicines,
    List<ShortageItem>? shortages,
    void Function(Medicine)? onMedicineMutated,
  }) {
    int mutatedCount = 0;
    final cleanCompId = updatedCompany.id.trim().toUpperCase();
    final cleanNewName = clean(updatedCompany.name);
    final cleanOldName = previousName != null ? clean(previousName) : "";
    final nowTs = DateTime.now().millisecondsSinceEpoch;

    for (var m in medicines) {
      final rawCid = m.companyId.trim();
      if (rawCid.isEmpty) continue;
      final cleanMedComp = clean(rawCid);
      final bool matched =
          (cleanCompId.isNotEmpty && rawCid.toUpperCase() == cleanCompId) ||
          (cleanOldName.isNotEmpty && cleanMedComp == cleanOldName) ||
          (cleanNewName.isNotEmpty && cleanMedComp == cleanNewName);

      if (matched) {
        bool changed = m.companyId != updatedCompany.id;
        m.companyId = updatedCompany.id;
        m.updatedAt = nowTs;
        m.version += 1;
        mutatedCount++;
        if (changed || previousName != null) {
          onMedicineMutated?.call(m);
        }
      }
    }

    if (shortages != null) {
      for (var s in shortages) {
        final rawSc = s.companyName.trim();
        if (rawSc.isEmpty) continue;
        final cleanSc = clean(rawSc);
        final bool matched =
            (cleanCompId.isNotEmpty && rawSc.toUpperCase() == cleanCompId) ||
            (cleanOldName.isNotEmpty && cleanSc == cleanOldName) ||
            (cleanNewName.isNotEmpty && cleanSc == cleanNewName);
        if (matched) {
          s.companyName = updatedCompany.name.trim().toUpperCase();
          mutatedCount++;
        }
      }
    }

    return mutatedCount;
  }

  /// 🔄 4. CASCADE SALT / COMPOSITION MASTER UPDATES TO PRODUCTS (#PH-REV-768)
  static int cascadeSaltUpdate({
    required Salt updatedSalt,
    String? previousName,
    required List<Medicine> medicines,
    void Function(Medicine)? onMedicineMutated,
  }) {
    int mutatedCount = 0;
    final cleanSaltId = updatedSalt.id.trim().toUpperCase();
    final cleanNewName = clean(updatedSalt.name);
    final cleanOldName = previousName != null ? clean(previousName) : "";
    final nowTs = DateTime.now().millisecondsSinceEpoch;

    for (var m in medicines) {
      final rawSid = m.saltId.trim();
      if (rawSid.isEmpty) continue;
      final cleanMedSalt = clean(rawSid);
      final bool matched =
          (cleanSaltId.isNotEmpty && rawSid.toUpperCase() == cleanSaltId) ||
          (cleanOldName.isNotEmpty && cleanMedSalt == cleanOldName) ||
          (cleanNewName.isNotEmpty && cleanMedSalt == cleanNewName);

      if (matched) {
        bool changed = m.saltId != updatedSalt.id;
        m.saltId = updatedSalt.id;
        m.updatedAt = nowTs;
        m.version += 1;
        mutatedCount++;
        if (changed || previousName != null) {
          onMedicineMutated?.call(m);
        }
      }
    }

    return mutatedCount;
  }

  /// 🔄 5. CASCADE ROUTE / AREA MASTER UPDATES TO ALL PARTIES (#PH-REV-768)
  static int cascadeRouteUpdate({
    required RouteArea updatedRoute,
    String? previousName,
    required List<Party> parties,
    void Function(Party)? onPartyMutated,
  }) {
    int mutatedCount = 0;
    final cleanRouteId = updatedRoute.id.trim().toUpperCase();
    final cleanNewName = clean(updatedRoute.name);
    final cleanOldName = previousName != null ? clean(previousName) : "";
    final targetRouteName = updatedRoute.name.trim().toUpperCase();
    final nowTs = DateTime.now().millisecondsSinceEpoch;

    for (var p in parties) {
      final rawRoute = p.route.trim();
      if (rawRoute.isEmpty) continue;
      final cleanPartyRoute = clean(rawRoute);
      final bool matched =
          (cleanRouteId.isNotEmpty && rawRoute.toUpperCase() == cleanRouteId) ||
          (cleanOldName.isNotEmpty && cleanPartyRoute == cleanOldName) ||
          (cleanNewName.isNotEmpty && cleanPartyRoute == cleanNewName);

      if (matched) {
        bool changed = p.route.trim().toUpperCase() != targetRouteName;
        p.route = targetRouteName;
        if (changed || previousName != null) {
          p.updatedAt = nowTs;
          p.version += 1;
          onPartyMutated?.call(p);
        }
        mutatedCount++;
      }
    }

    return mutatedCount;
  }

  /// 🔍 UNIVERSAL HELPER: Resolve Company Name from ID or literal string
  static String resolveCompanyName(String idOrName, List<Company> companies, {String fallback = "N/A"}) {
    final raw = idOrName.trim();
    if (raw.isEmpty) return fallback;
    final upper = raw.toUpperCase();
    final cl = clean(raw);
    for (final c in companies) {
      if (c.id.trim().toUpperCase() == upper) return c.name;
      if (cl.isNotEmpty && clean(c.name) == cl) return c.name;
    }
    return raw;
  }

  /// 🔍 UNIVERSAL HELPER: Resolve Salt Name from ID or literal string
  static String resolveSaltName(String idOrName, List<Salt> salts, {String fallback = "N/A"}) {
    final raw = idOrName.trim();
    if (raw.isEmpty) return fallback;
    final upper = raw.toUpperCase();
    final cl = clean(raw);
    for (final s in salts) {
      if (s.id.trim().toUpperCase() == upper) return s.name;
      if (cl.isNotEmpty && clean(s.name) == cl) return s.name;
    }
    return raw;
  }

  /// 🔍 UNIVERSAL HELPER: Check if Medicine belongs to Company
  static bool belongsToCompany(Medicine m, Company c) {
    final raw = m.companyId.trim();
    if (raw.isEmpty) return false;
    if (c.id.trim().isNotEmpty && raw.toUpperCase() == c.id.trim().toUpperCase()) return true;
    final clComp = clean(c.name);
    return clComp.isNotEmpty && clean(raw) == clComp;
  }

  /// 🔍 UNIVERSAL HELPER: Check if Medicine belongs to Salt
  static bool belongsToSalt(Medicine m, Salt s) {
    final raw = m.saltId.trim();
    if (raw.isEmpty) return false;
    if (s.id.trim().isNotEmpty && raw.toUpperCase() == s.id.trim().toUpperCase()) return true;
    final clSalt = clean(s.name);
    return clSalt.isNotEmpty && clean(raw) == clSalt;
  }

  /// 🔍 UNIVERSAL HELPER: Check if Party belongs to RouteArea
  static bool belongsToRoute(Party p, RouteArea r) {
    final raw = p.route.trim();
    if (raw.isEmpty) return false;
    if (r.id.trim().isNotEmpty && raw.toUpperCase() == r.id.trim().toUpperCase()) return true;
    final clRoute = clean(r.name);
    return clRoute.isNotEmpty && clean(raw) == clRoute;
  }
}
