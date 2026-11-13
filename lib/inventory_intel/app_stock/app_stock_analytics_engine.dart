// FILE: lib/inventory_intel/app_stock/app_stock_analytics_engine.dart
import 'package:flutter/material.dart';
import 'package:pharoah_erp/expiry_master.dart';
import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';

class VendorInwardSummary {
  final String vendorName;
  final String vendorId;
  final int purchaseCount;
  final double totalQty;
  final double minRate;
  final double maxRate;
  final double latestRate;
  final double firstRate;
  final double priceChangePct;
  final DateTime lastDate;

  VendorInwardSummary({
    required this.vendorName,
    required this.vendorId,
    required this.purchaseCount,
    required this.totalQty,
    required this.minRate,
    required this.maxRate,
    required this.latestRate,
    required this.firstRate,
    required this.priceChangePct,
    required this.lastDate,
  });

  bool get isHike => priceChangePct > 0.5;
  bool get isDrop => priceChangePct < -0.5;
}

class AppStockAnalyticsEngine {
  static String resolveCompanyName(PharoahManager ph, String companyId) {
    if (companyId.trim().isEmpty) return "Unassigned";
    final upper = companyId.trim().toUpperCase();
    for (final c in ph.companies) {
      if (c.id == companyId || c.name.trim().toUpperCase() == upper) {
        return c.name;
      }
    }
    return companyId;
  }

  static bool hasPriceHike(PharoahManager ph, Medicine med) {
    final cleanName = med.name.trim().toUpperCase();
    final matchingInwards = <Map<String, dynamic>>[];
    for (final p in ph.purchases) {
      if (p.isDeleted == 1) continue;
      for (final it in p.items) {
        if (it.medicineID == med.id ||
            (med.systemId.isNotEmpty && it.medicineID == med.systemId) ||
            it.name.trim().toUpperCase() == cleanName) {
          matchingInwards.add({'date': p.date, 'rate': it.purchaseRate});
        }
      }
    }
    if (matchingInwards.length < 2) return false;
    matchingInwards.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return (matchingInwards.last['rate'] as double) > (matchingInwards.first['rate'] as double);
  }

  static String getNearestExpiry(PharoahManager ph, Medicine med) {
    final batches = ph.getBatchesForMedicine(med);
    final active = batches
        .where((b) => b.qty > 0 && !ExpiryMaster.isNonExpiryValue(b.exp))
        .toList();
    if (active.isEmpty) return "-";
    active.sort(
      (a, b) => ExpiryMaster.parseToEndOfMonth(a.exp)
          .compareTo(ExpiryMaster.parseToEndOfMonth(b.exp)),
    );
    return active.first.exp;
  }

  static bool isExpiringSoon(PharoahManager ph, Medicine med, {int days = 90}) {
    final exp = getNearestExpiry(ph, med);
    if (exp == "-") return false;
    final expDate = ExpiryMaster.parseToEndOfMonth(exp);
    final today = DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day).add(Duration(days: days));
    return !expDate.isAfter(cutoff);
  }

  static double computePurValuation(PharoahManager ph, Medicine m) {
    if (m.stock <= 0) return 0.0;
    final active = ph.getBatchesForMedicine(m).where((b) => b.qty > 0).toList();
    if (active.isEmpty) return m.stock * m.purRate;
    final double batchQtySum = active.fold(0.0, (sum, b) => sum + b.qty);
    if ((batchQtySum - m.stock).abs() <= 0.01) {
      return active.fold(0.0, (sum, b) {
        final double raw = b.purRate > 0 ? b.purRate : b.rate;
        final double r = raw > 0 ? raw : m.purRate;
        return sum + (b.qty * r);
      });
    }
    return m.stock * m.purRate;
  }

  static double computeMrpValuation(PharoahManager ph, Medicine m) {
    if (m.stock <= 0) return 0.0;
    final active = ph.getBatchesForMedicine(m).where((b) => b.qty > 0).toList();
    if (active.isEmpty) return m.stock * m.mrp;
    final double batchQtySum = active.fold(0.0, (sum, b) => sum + b.qty);
    if ((batchQtySum - m.stock).abs() <= 0.01) {
      return active.fold(0.0, (sum, b) {
        final double r = b.mrp > 0 ? b.mrp : m.mrp;
        return sum + (b.qty * r);
      });
    }
    return m.stock * m.mrp;
  }

  /// Gathers all 360° stock movement events matching Web StockMovementLedgerModal
  static ({
    List<Map<String, dynamic>> rawTxns,
    List<String> batchLabels,
  }) buildMovementTransactions(PharoahManager ph, Medicine medicine) {
    final cleanMedName = medicine.name.trim().toUpperCase();
    final medId = medicine.id;
    final sysId = medicine.systemId;
    final idKey = medicine.identityKey;

    bool matchesItem(String itMedId, String itName) {
      if (medId.isNotEmpty && itMedId == medId) return true;
      if (sysId.isNotEmpty && itMedId == sysId) return true;
      if (idKey.isNotEmpty && itMedId == idKey) return true;
      if (cleanMedName.isNotEmpty && itName.trim().toUpperCase() == cleanMedName) {
        return true;
      }
      return false;
    }

    String batchLabel(String raw) => raw.trim().isEmpty ? "NO BATCH" : raw.trim();

    final List<Map<String, dynamic>> rawTxns = [];
    final batchesInHistory = ph.getBatchesForMedicine(medicine);
    final DateTime openingDate = DateTime(2000, 1, 1);

    // 0. Opening Stock & Manual Adjustments
    for (final b in batchesInHistory) {
      final bDisp = batchLabel(b.batch);
      final double bRate = b.purRate > 0 ? b.purRate : b.rate;

      if (b.openingQty != 0) {
        rawTxns.add({
          'date': openingDate,
          'type': 'OPENING',
          'typeLabel': 'Opening Stock',
          'docNo': 'OPENING',
          'party': 'Opening Balance',
          'batch': bDisp,
          'exp': b.exp,
          'inQty': b.openingQty > 0 ? b.openingQty : 0.0,
          'outQty': b.openingQty < 0 ? b.openingQty.abs() : 0.0,
          'rate': bRate,
          'color': const Color(0xFF0284C7),
          'icon': Icons.inventory_rounded,
          'sortOrder': 0,
        });
      }

      if (b.adjustmentHistory.isNotEmpty) {
        for (final adj in b.adjustmentHistory) {
          if (adj.adjustmentQty == 0) continue;
          rawTxns.add({
            'date': adj.timestamp > 0
                ? DateTime.fromMillisecondsSinceEpoch(adj.timestamp)
                : DateTime.now(),
            'type': 'ADJUSTMENT',
            'typeLabel': adj.reason.isNotEmpty ? "Stock Adj (${adj.reason})" : "Stock Adjustment",
            'docNo': adj.id,
            'party': adj.adjustedBy.isNotEmpty ? adj.adjustedBy : "Manual Audit",
            'batch': bDisp,
            'exp': b.exp,
            'inQty': adj.adjustmentQty > 0 ? adj.adjustmentQty : 0.0,
            'outQty': adj.adjustmentQty < 0 ? adj.adjustmentQty.abs() : 0.0,
            'rate': bRate,
            'color': const Color(0xFFD97706),
            'icon': Icons.tune_rounded,
            'sortOrder': 2,
          });
        }
      } else if (b.adjustmentQty != 0) {
        rawTxns.add({
          'date': b.updatedAt > 0
              ? DateTime.fromMillisecondsSinceEpoch(b.updatedAt)
              : DateTime.now(),
          'type': 'ADJUSTMENT',
          'typeLabel': b.adjReason.isNotEmpty ? "Stock Adj (${b.adjReason})" : "Stock Adjustment",
          'docNo': 'ADJ',
          'party': 'Manual Audit',
          'batch': bDisp,
          'exp': b.exp,
          'inQty': b.adjustmentQty > 0 ? b.adjustmentQty : 0.0,
          'outQty': b.adjustmentQty < 0 ? b.adjustmentQty.abs() : 0.0,
          'rate': bRate,
          'color': const Color(0xFFD97706),
          'icon': Icons.tune_rounded,
          'sortOrder': 2,
        });
      }
    }

    // 1. Purchases (IN)
    for (final p in ph.purchases) {
      if (p.isDeleted == 1) continue;
      for (final it in p.items) {
        if (matchesItem(it.medicineID, it.name)) {
          rawTxns.add({
            'date': p.date,
            'type': 'PURCHASE',
            'typeLabel': 'Purchase Inward',
            'docNo': p.billNo.isNotEmpty ? p.billNo : p.internalNo,
            'party': p.distributorName.isNotEmpty ? p.distributorName : 'Supplier',
            'batch': batchLabel(it.batch),
            'exp': it.exp,
            'inQty': it.qty + it.freeQty,
            'outQty': 0.0,
            'rate': it.purchaseRate,
            'color': const Color(0xFF047857),
            'icon': Icons.downloading_rounded,
            'sortOrder': 1,
          });
        }
      }
    }

    // 2. Sales (OUT)
    for (final s in ph.sales) {
      if (s.isDeleted == 1 || s.status.toUpperCase() == "CANCELLED") continue;
      for (final it in s.items) {
        if (matchesItem(it.medicineID, it.name)) {
          rawTxns.add({
            'date': s.date,
            'type': 'SALE',
            'typeLabel': 'Sale Invoice',
            'docNo': s.billNo,
            'party': s.partyName.isNotEmpty ? s.partyName : 'Counter Customer',
            'batch': batchLabel(it.batch),
            'exp': it.exp,
            'inQty': 0.0,
            'outQty': it.qty + it.freeQty,
            'rate': it.rate,
            'color': const Color(0xFF0369A1),
            'icon': Icons.shopping_cart_checkout_rounded,
            'sortOrder': 1,
          });
        }
      }
    }

    // 3. Sale Returns / Credit Notes
    for (final r in ph.saleReturns) {
      if (r.isDeleted == 1 || r.status.toUpperCase() == "CANCELLED") continue;
      for (final it in r.items) {
        if (matchesItem(it.medicineID, it.name)) {
          final bool isSellable = !it.isBreakage;
          rawTxns.add({
            'date': r.date,
            'type': 'CREDIT_NOTE',
            'typeLabel': isSellable ? 'Credit Note (Return In +)' : 'Credit Note (Breakage/Exp)',
            'docNo': r.billNo,
            'party': r.partyName,
            'batch': batchLabel(it.batch),
            'exp': it.exp,
            'inQty': isSellable ? (it.qty + it.freeQty) : 0.0,
            'outQty': 0.0,
            'rate': it.rate,
            'color': const Color(0xFF7C3AED),
            'icon': Icons.assignment_return_rounded,
            'sortOrder': 1,
          });
        }
      }
    }

    // 4. Purchase Returns / Debit Notes
    for (final r in ph.purchaseReturns) {
      if (r.isDeleted == 1 || r.status.toUpperCase() == "CANCELLED") continue;
      for (final it in r.items) {
        if (matchesItem(it.medicineID, it.name)) {
          rawTxns.add({
            'date': r.date,
            'type': 'DEBIT_NOTE',
            'typeLabel': 'Debit Note (Return Out -)',
            'docNo': r.billNo,
            'party': r.distributorName,
            'batch': batchLabel(it.batch),
            'exp': it.exp,
            'inQty': 0.0,
            'outQty': it.qty + it.freeQty,
            'rate': it.purchaseRate,
            'color': const Color(0xFFDC2626),
            'icon': Icons.remove_shopping_cart_rounded,
            'sortOrder': 1,
          });
        }
      }
    }

    // Sort chronologically ascending with Opening Stock first
    rawTxns.sort((a, b) {
      final int soA = (a['sortOrder'] as int?) ?? 1;
      final int soB = (b['sortOrder'] as int?) ?? 1;
      if (soA == 0 && soB != 0) return -1;
      if (soB == 0 && soA != 0) return 1;
      return (a['date'] as DateTime).compareTo(b['date'] as DateTime);
    });

    final Set<String> allBatches = {};
    for (final t in rawTxns) {
      final b = (t['batch'] as String?) ?? '';
      if (b.isNotEmpty) allBatches.add(b);
    }
    for (final b in batchesInHistory) {
      allBatches.add(batchLabel(b.batch));
    }

    return (rawTxns: rawTxns, batchLabels: allBatches.toList()..sort());
  }

  /// Gathers all vendor inward records & comparative rate summaries
  static ({
    List<Map<String, dynamic>> inwardRecords,
    List<VendorInwardSummary> vendorSummaries,
    double overallMinRate,
    double overallMaxRate,
  }) buildVendorInwardRecords(PharoahManager ph, Medicine medicine) {
    final cleanMedName = medicine.name.trim().toUpperCase();
    final List<Map<String, dynamic>> inwardRecords = [];

    for (final pur in ph.purchases) {
      if (pur.isDeleted == 1) continue;
      for (final it in pur.items) {
        final bool matches = it.medicineID == medicine.id ||
            (medicine.systemId.isNotEmpty && it.medicineID == medicine.systemId) ||
            (medicine.identityKey.isNotEmpty && it.medicineID == medicine.identityKey) ||
            (it.name.trim().toUpperCase() == cleanMedName &&
                it.packing.trim().toUpperCase() == medicine.packing.trim().toUpperCase());
        if (matches) {
          double effRate = it.purchaseRate;
          if (it.discountPer > 0) {
            effRate = it.purchaseRate * (1 - (it.discountPer / 100));
          } else if (it.discountRupees > 0 && it.qty > 0) {
            effRate = it.purchaseRate - (it.discountRupees / it.qty);
          }
          inwardRecords.add({
            'purchase': pur,
            'item': it,
            'vendor': pur.distributorName.trim().isNotEmpty
                ? pur.distributorName.trim()
                : "Direct Supplier",
            'vendorId': pur.partyId,
            'date': pur.date,
            'billNo': pur.billNo.isNotEmpty ? pur.billNo : pur.internalNo,
            'batch': it.batch,
            'exp': it.exp,
            'qty': it.qty,
            'freeQty': it.freeQty,
            'rawRate': it.purchaseRate,
            'discPer': it.discountPer,
            'effRate': effRate,
            'mrp': it.mrp > 0 ? it.mrp : medicine.mrp,
          });
        }
      }
    }

    inwardRecords.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final r in inwardRecords) {
      final vName = r['vendor'] as String;
      grouped.putIfAbsent(vName, () => []).add(r);
    }

    final List<VendorInwardSummary> summaries = [];
    double overallMinRate = double.infinity;
    double overallMaxRate = 0.0;

    for (final entry in grouped.entries) {
      final recs = entry.value;
      recs.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
      final double firstRate = recs.first['effRate'] as double;
      final double latestRate = recs.last['effRate'] as double;
      double minR = double.infinity;
      double maxR = 0.0;
      double totalQ = 0.0;

      for (final r in recs) {
        final er = r['effRate'] as double;
        if (er < minR) minR = er;
        if (er > maxR) maxR = er;
        if (er < overallMinRate) overallMinRate = er;
        if (er > overallMaxRate) overallMaxRate = er;
        totalQ += (r['qty'] as double) + (r['freeQty'] as double);
      }

      final double pct = firstRate > 0 ? ((latestRate - firstRate) / firstRate) * 100 : 0.0;
      summaries.add(
        VendorInwardSummary(
          vendorName: entry.key,
          vendorId: (recs.first['vendorId'] as String?) ?? '',
          purchaseCount: recs.length,
          totalQty: totalQ,
          minRate: minR == double.infinity ? 0.0 : minR,
          maxRate: maxR,
          latestRate: latestRate,
          firstRate: firstRate,
          priceChangePct: pct,
          lastDate: recs.last['date'] as DateTime,
        ),
      );
    }

    summaries.sort((a, b) => a.latestRate.compareTo(b.latestRate));
    return (
      inwardRecords: inwardRecords,
      vendorSummaries: summaries,
      overallMinRate: overallMinRate == double.infinity ? 0.0 : overallMinRate,
      overallMaxRate: overallMaxRate,
    );
  }
}
