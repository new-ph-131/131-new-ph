import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/web_models.dart';

/// WebSyncExtension: Attaches clean, safe sync hooks to PharoahWebManager
/// ensuring Web edits preserve IDs, deletions log tombstones, and debounced auto-sync triggers.
extension WebSyncExtension on PharoahWebManager {
  /// Safe Edit for Web Sales: Preserves ID and tombstoned previousId if changed
  Future<void> syncWebUpdateSale(Sale updatedSale, {String? previousId}) async {
    if (previousId != null &&
        previousId.isNotEmpty &&
        previousId != updatedSale.id) {
      deletedRecordIds.add(previousId);
    }

    final int idx = sales.indexWhere((s) => s.id == updatedSale.id || s.billNo == updatedSale.billNo);
    if (idx != -1) {
      sales[idx] = updatedSale;
    } else {
      sales.add(updatedSale);
    }

    for (final item in updatedSale.items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey;
      } catch (_) {}
      registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.rate,
        rateA: item.appliedRateType == "A" ? item.rate : 0.0,
        rateB: item.appliedRateType == "B" ? item.rate : 0.0,
        rateC: item.appliedRateType == "C" ? item.rate : 0.0,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }

    rebuildInventory();
    await pushUpdatedDataToCloud();
  }

  /// Safe Delete for Web Sales: Ensures ID is recorded in tombstones
  void syncWebDeleteSale(String saleId, {String? billNo}) {
    deleteSale(saleId);
    if (billNo != null && billNo.trim().isNotEmpty) {
      deletedRecordIds.add(billNo.trim());
    }
  }

  /// Safe Edit for Web Purchases: Preserves ID and syncs delta
  Future<void> syncWebUpdatePurchase(Purchase updatedPurchase, {String? previousId}) async {
    if (previousId != null &&
        previousId.isNotEmpty &&
        previousId != updatedPurchase.id) {
      deletedRecordIds.add(previousId);
    }

    final int idx = purchases.indexWhere((p) => p.id == updatedPurchase.id || p.internalNo == updatedPurchase.internalNo);
    if (idx != -1) {
      purchases[idx] = updatedPurchase;
    } else {
      purchases.add(updatedPurchase);
    }

    for (final item in updatedPurchase.items) {
      String resolvedKey = item.medicineID;
      try {
        final med = medicines.firstWhere((m) => m.id == item.medicineID);
        resolvedKey = med.identityKey;
      } catch (_) {}
      registerBatchActivity(
        productKey: resolvedKey,
        batchNo: item.batch,
        exp: item.exp,
        packing: item.packing,
        mrp: item.mrp,
        rate: item.purchaseRate,
        rateA: item.rateA,
        rateB: item.rateB,
        rateC: item.rateC,
        rateCFormula: item.rateCFormula,
        appliedRateType: item.appliedRateType,
      );
    }

    rebuildInventory();
    await pushUpdatedDataToCloud();
  }

  /// Safe Delete for Web Purchases: Ensures ID is recorded in tombstones
  void syncWebDeletePurchase(String purchaseId, {String? billNo}) {
    deletePurchase(purchaseId);
    if (billNo != null && billNo.trim().isNotEmpty) {
      deletedRecordIds.add(billNo.trim());
    }
  }

  /// Safe Edit for Web Vouchers
  Future<void> syncWebUpdateVoucher(Voucher updatedVoucher, {String? previousId}) async {
    if (previousId != null &&
        previousId.isNotEmpty &&
        previousId != updatedVoucher.id) {
      deletedRecordIds.add(previousId);
    }

    final int idx = vouchers.indexWhere((v) => v.id == updatedVoucher.id || v.voucherNo == updatedVoucher.voucherNo);
    if (idx != -1) {
      vouchers[idx] = updatedVoucher;
    } else {
      vouchers.add(updatedVoucher);
    }

    await pushUpdatedDataToCloud();
  }

  /// Safe Delete for Web Vouchers
  void syncWebDeleteVoucher(String voucherId, {String? voucherNo}) {
    deleteVoucher(voucherId);
    if (voucherNo != null && voucherNo.trim().isNotEmpty) {
      deletedRecordIds.add(voucherNo.trim());
    }
  }
}
