import '../pharoah_manager.dart';
import '../models.dart';
import '../inventory_logic_center.dart';
import 'engines/app_auto_sync_daemon.dart';
import 'interceptors/sync_action_orchestrator.dart';

/// PharoahSyncExtension: Attaches clean, non-invasive sync hooks to PharoahManager
/// without altering or modifying the original lib core files.
extension PharoahSyncExtension on PharoahManager {
  /// Initializes the silent background auto-sync daemon on the App
  void activateAutoSyncEngine() {
    AppAutoSyncDaemon.instance.triggerSilentPush(this);
    AppAutoSyncDaemon.instance.startHeartbeat(this);
  }

  /// Safe Edit for Sales: Preserves ID and triggers background sync
  Future<void> syncUpdateSale(Sale updatedSale, {String? previousId}) async {
    final int idx = sales.indexWhere((s) => s.id == updatedSale.id || s.billNo == updatedSale.billNo);
    if (idx != -1) {
      sales[idx] = updatedSale;
    } else {
      sales.add(updatedSale);
    }

    InventoryLogicCenter.rebuildAllInventory(
      medicines: medicines,
      batchHistory: batchHistory,
      purchases: purchases,
      sales: sales,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
    );

    await save();

    await SyncActionOrchestrator.instance.onSaleSaved(
      ph: this,
      sale: updatedSale,
      previousId: previousId,
    );
  }

  /// Safe Delete for Sales: Permanently logs tombstone and syncs to cloud
  Future<void> syncDeleteSale(String saleId, {String? billNo}) async {
    deleteBill(saleId);
    await SyncActionOrchestrator.instance.onSaleDeleted(
      ph: this,
      saleId: saleId,
      billNo: billNo,
    );
  }

  /// Safe Edit for Purchases: Preserves ID and triggers background sync
  Future<void> syncUpdatePurchase(Purchase updatedPurchase, {String? previousId}) async {
    final int idx = purchases.indexWhere((p) => p.id == updatedPurchase.id || p.internalNo == updatedPurchase.internalNo);
    if (idx != -1) {
      purchases[idx] = updatedPurchase;
    } else {
      purchases.add(updatedPurchase);
    }

    InventoryLogicCenter.rebuildAllInventory(
      medicines: medicines,
      batchHistory: batchHistory,
      purchases: purchases,
      sales: sales,
      saleReturns: saleReturns,
      purchaseReturns: purchaseReturns,
    );

    await save();

    await SyncActionOrchestrator.instance.onPurchaseSaved(
      ph: this,
      purchase: updatedPurchase,
      previousId: previousId,
    );
  }

  /// Safe Delete for Purchases: Permanently logs tombstone and syncs to cloud
  Future<void> syncDeletePurchase(String purchaseId, {String? billNo}) async {
    deletePurchase(purchaseId);
    await SyncActionOrchestrator.instance.onPurchaseDeleted(
      ph: this,
      purchaseId: purchaseId,
      billNo: billNo,
    );
  }

  /// Safe Edit for Vouchers: Preserves ID and triggers background sync
  Future<void> syncUpdateVoucher(Voucher updatedVoucher, {String? previousId}) async {
    final int idx = vouchers.indexWhere((v) => v.id == updatedVoucher.id || v.voucherNo == updatedVoucher.voucherNo);
    if (idx != -1) {
      vouchers[idx] = updatedVoucher;
    } else {
      vouchers.add(updatedVoucher);
    }

    await save();

    await SyncActionOrchestrator.instance.onVoucherSaved(
      ph: this,
      voucher: updatedVoucher,
      previousId: previousId,
    );
  }

  /// Safe Delete for Vouchers: Permanently logs tombstone and syncs to cloud
  Future<void> syncDeleteVoucher(String voucherId, {String? voucherNo}) async {
    deleteVoucher(voucherId);
    await SyncActionOrchestrator.instance.onVoucherDeleted(
      ph: this,
      voucherId: voucherId,
      voucherNo: voucherNo,
    );
  }

  /// Safe Delete for Challans: Permanently logs tombstone and syncs to cloud
  Future<void> syncDeleteChallan(String challanId, {String? challanNo, bool isSale = true}) async {
    if (isSale) {
      deleteSaleChallan(challanId);
    } else {
      deletePurchaseChallan(challanId);
    }
    await SyncActionOrchestrator.instance.onChallanDeleted(
      ph: this,
      challanId: challanId,
      challanNo: challanNo,
    );
  }

  /// Safe Delete for Returns: Permanently logs tombstone and syncs to cloud
  Future<void> syncDeleteReturn(String returnId, {String? returnNo, bool isSale = true}) async {
    if (isSale) {
      deleteSaleReturn(returnId);
    } else {
      deletePurchaseReturn(returnId);
    }
    await SyncActionOrchestrator.instance.onReturnDeleted(
      ph: this,
      returnId: returnId,
      returnNo: returnNo,
    );
  }
}
