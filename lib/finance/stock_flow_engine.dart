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
    double received = 0.0;
    double sold = 0.0;

    // 1. Inward (Purchases) scan karein
    for (var p in ph.purchases.where((p) => p.date.isAfter(from.subtract(const Duration(seconds: 1))) && p.date.isBefore(to.add(const Duration(days: 1))))) {
      for (var it in p.items.where((it) => it.medicineID == med.id)) {
        received += (it.qty + it.freeQty);
      }
    }

    // 2. Outward (Sales) scan karein
    for (var s in ph.sales.where((s) => s.status == "Active" && s.date.isAfter(from.subtract(const Duration(seconds: 1))) && s.date.isBefore(to.add(const Duration(days: 1))))) {
      for (var it in s.items.where((it) => it.medicineID == med.id)) {
        sold += (it.qty + it.freeQty);
      }
    }

    // 3. Returns Adjustment (Pharma Professional logic)
    // Sale Return (CN) = Stock vapas aaya (Received jaisa treatment)
    for (var r in ph.saleReturns.where((r) => r.status == "Active" && r.date.isAfter(from) && r.date.isBefore(to))) {
      for (var it in r.items.where((it) => it.medicineID == med.id && it.isBreakage == false)) {
        received += (it.qty + it.freeQty);
      }
    }

    // 4. Back-Calculation Logic
    // Closing aaj ka current stock hai (Kyuki app live hai)
    double closing = med.stock; 
    // Opening = Closing + Outflow - Inflow
    // (Range ke bahar ki transactions ko adjust karke opening nikalna)
    double opening = closing - received + sold;

    return {
      'opening': opening,
      'received': received,
      'sale': sold,
      'closing': closing,
    };
  }
}
