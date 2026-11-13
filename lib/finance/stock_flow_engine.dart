import '../models.dart';
import '../pharoah_manager.dart';

class StockFlowEngine {
  /// Sabse Mahtvapurn Logic: Ek specific date range ke liye stock ki ginti karna
  static Map<String, double> getItemFlow({
    required Medicine med,
    required DateTime from,
    required DateTime to,
    required PharoahManager ph,
  }) {
    final DateTime fromStart = DateTime(from.year, from.month, from.day);
    final DateTime toEnd = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
    bool matchesMed(String mId) =>
        mId == med.id || (med.identityKey.isNotEmpty && mId == med.identityKey);

    double purBefore = 0.0, purIn = 0.0;
    double saleBefore = 0.0, saleIn = 0.0;
    double cnBefore = 0.0, cnIn = 0.0;
    double dnBefore = 0.0, dnIn = 0.0;

    for (var p in ph.purchases.where((p) => p.isDeleted != 1)) {
      for (var it in p.items.where((it) => matchesMed(it.medicineID))) {
        final q = it.qty + it.freeQty;
        if (p.date.isBefore(fromStart)) {
          purBefore += q;
        } else if (!p.date.isAfter(toEnd)) {
          purIn += q;
        }
      }
    }

    for (var s in ph.sales.where((s) => s.isDeleted != 1 && (s.status.isEmpty || s.status == "Active"))) {
      for (var it in s.items.where((it) => matchesMed(it.medicineID))) {
        final q = it.qty + it.freeQty;
        if (s.date.isBefore(fromStart)) {
          saleBefore += q;
        } else if (!s.date.isAfter(toEnd)) {
          saleIn += q;
        }
      }
    }

    for (var r in ph.saleReturns.where((r) => r.isDeleted != 1 && (r.status.isEmpty || r.status == "Active"))) {
      for (var it in r.items.where((it) => matchesMed(it.medicineID) && !it.isBreakage)) {
        final q = it.qty + it.freeQty;
        if (r.date.isBefore(fromStart)) {
          cnBefore += q;
        } else if (!r.date.isAfter(toEnd)) {
          cnIn += q;
        }
      }
    }

    for (var r in ph.purchaseReturns.where((r) => r.isDeleted != 1 && (r.status.isEmpty || r.status == "Active"))) {
      for (var it in r.items.where((it) => matchesMed(it.medicineID))) {
        final q = it.qty + it.freeQty;
        if (r.date.isBefore(fromStart)) {
          dnBefore += q;
        } else if (!r.date.isAfter(toEnd)) {
          dnIn += q;
        }
      }
    }

    double baseOpening = 0.0;
    final batches = ph.batchHistory[med.identityKey] ?? [];
    if (batches.isNotEmpty) {
      baseOpening = batches.fold(0.0, (sum, b) => sum + b.openingQty + b.adjustmentQty);
    } else if (!ph.batchHistory.containsKey(med.identityKey)) {
      double allPur = 0.0, allSale = 0.0, allCn = 0.0, allDn = 0.0;
      for (var p in ph.purchases.where((p) => p.isDeleted != 1)) {
        for (var it in p.items.where((it) => matchesMed(it.medicineID))) allPur += (it.qty + it.freeQty);
      }
      for (var s in ph.sales.where((s) => s.isDeleted != 1 && (s.status.isEmpty || s.status == "Active"))) {
        for (var it in s.items.where((it) => matchesMed(it.medicineID))) allSale += (it.qty + it.freeQty);
      }
      for (var r in ph.saleReturns.where((r) => r.isDeleted != 1 && (r.status.isEmpty || r.status == "Active"))) {
        for (var it in r.items.where((it) => matchesMed(it.medicineID) && !it.isBreakage)) allCn += (it.qty + it.freeQty);
      }
      for (var r in ph.purchaseReturns.where((r) => r.isDeleted != 1 && (r.status.isEmpty || r.status == "Active"))) {
        for (var it in r.items.where((it) => matchesMed(it.medicineID))) allDn += (it.qty + it.freeQty);
      }
      baseOpening = med.stock - allPur + allSale - allCn + allDn;
    }

    final double opening = baseOpening + purBefore - saleBefore + cnBefore - dnBefore;
    final double received = purIn + cnIn;
    final double sold = saleIn + dnIn;
    final double closing = opening + received - sold;

    return {
      'opening': opening,
      'received': received,
      'sale': sold,
      'closing': closing,
    };
  }
}
