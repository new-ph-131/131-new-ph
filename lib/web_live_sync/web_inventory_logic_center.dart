// FILE: lib/web_live_sync/web_inventory_logic_center.dart

import '../../inventory_logic_center.dart';
import 'web_models.dart';

class WebInventoryLogicCenter {
  /// Web In-Memory Total Stock Valuation
  static double calculateTotalStockValue({
    required Map<String, List<BatchInfo>> batchHistory,
    required List<Medicine> medicines,
  }) {
    return InventoryLogicCenter.calculateTotalStockValue(
      batchHistory: batchHistory,
      medicines: medicines,
    );
  }

  /// Web Full Inventory Rebuild Engine
  /// Formula: Batch Qty = Opening + Adjustments + Purchases - Sales + Sellable Returns - Debit Notes
  static void rebuildWebInventory({
    required List<Medicine> medicines,
    required Map<String, List<BatchInfo>> batchHistory,
    required List<Purchase> purchases,
    required List<Sale> sales,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
  }) {
    InventoryLogicCenter.rebuildAllInventory(
      medicines: medicines,
      batchHistory: batchHistory,
      purchases: purchases,
      sales: sales,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
    );
  }
}
