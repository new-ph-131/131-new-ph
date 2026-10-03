import 'package:pharoah_erp/models.dart';
import 'package:pharoah_erp/pharoah_manager.dart';
import '../core/sync_tombstone_hub.dart';
import '../engines/app_auto_sync_daemon.dart';

/// SyncActionOrchestrator: Central mediator that intercepts all Add, Edit, Modify,
/// and Delete operations across all entities, ensuring consistent ID persistence,
/// permanent tombstone recording, and background cloud pushes.
class SyncActionOrchestrator {
  static final SyncActionOrchestrator instance = SyncActionOrchestrator._internal();
  SyncActionOrchestrator._internal();

  // ==========================================
  // 1. SALES INVOICE INTERCEPTORS
  // ==========================================
  Future<void> onSaleSaved({
    required PharoahManager ph,
    required Sale sale,
    String? previousId,
  }) async {
    final workingDir = await ph.getWorkingPath();
    final companyId = ph.activeCompany?.id ?? '';

    // If an edit generated a new ID, mark the previous ghost ID as tombstoned
    if (previousId != null &&
        previousId.isNotEmpty &&
        previousId != sale.id &&
        companyId.isNotEmpty) {
      await SyncTombstoneHub.markDeleted(
        workingDir: workingDir,
        companyId: companyId,
        id: previousId,
      );
    }

    AppAutoSyncDaemon.instance.triggerSilentPush(ph);
  }

  Future<void> onSaleDeleted({
    required PharoahManager ph,
    required String saleId,
    String? billNo,
  }) async {
    final workingDir = await ph.getWorkingPath();
    final companyId = ph.activeCompany?.id ?? '';

    if (companyId.isNotEmpty) {
      await SyncTombstoneHub.markDeleted(
        workingDir: workingDir,
        companyId: companyId,
        id: saleId,
        referenceNo: billNo,
      );
    }

    AppAutoSyncDaemon.instance.triggerSilentPush(ph);
  }

  // ==========================================
  // 2. PURCHASE INWARD INTERCEPTORS
  // ==========================================
  Future<void> onPurchaseSaved({
    required PharoahManager ph,
    required Purchase purchase,
    String? previousId,
  }) async {
    final workingDir = await ph.getWorkingPath();
    final companyId = ph.activeCompany?.id ?? '';

    if (previousId != null &&
        previousId.isNotEmpty &&
        previousId != purchase.id &&
        companyId.isNotEmpty) {
      await SyncTombstoneHub.markDeleted(
        workingDir: workingDir,
        companyId: companyId,
        id: previousId,
      );
    }

    AppAutoSyncDaemon.instance.triggerSilentPush(ph);
  }

  Future<void> onPurchaseDeleted({
    required PharoahManager ph,
    required String purchaseId,
    String? billNo,
  }) async {
    final workingDir = await ph.getWorkingPath();
    final companyId = ph.activeCompany?.id ?? '';

    if (companyId.isNotEmpty) {
      await SyncTombstoneHub.markDeleted(
        workingDir: workingDir,
        companyId: companyId,
        id: purchaseId,
        referenceNo: billNo,
      );
    }

    AppAutoSyncDaemon.instance.triggerSilentPush(ph);
  }

  // ==========================================
  // 3. VOUCHER (RECEIPT/PAYMENT/CONTRA) INTERCEPTORS
  // ==========================================
  Future<void> onVoucherSaved({
    required PharoahManager ph,
    required Voucher voucher,
    String? previousId,
  }) async {
    final workingDir = await ph.getWorkingPath();
    final companyId = ph.activeCompany?.id ?? '';

    if (previousId != null &&
        previousId.isNotEmpty &&
        previousId != voucher.id &&
        companyId.isNotEmpty) {
      await SyncTombstoneHub.markDeleted(
        workingDir: workingDir,
        companyId: companyId,
        id: previousId,
      );
    }

    AppAutoSyncDaemon.instance.triggerSilentPush(ph);
  }

  Future<void> onVoucherDeleted({
    required PharoahManager ph,
    required String voucherId,
    String? voucherNo,
  }) async {
    final workingDir = await ph.getWorkingPath();
    final companyId = ph.activeCompany?.id ?? '';

    if (companyId.isNotEmpty) {
      await SyncTombstoneHub.markDeleted(
        workingDir: workingDir,
        companyId: companyId,
        id: voucherId,
        referenceNo: voucherNo,
      );
    }

    AppAutoSyncDaemon.instance.triggerSilentPush(ph);
  }

  // ==========================================
  // 4. CHALLANS & RETURNS INTERCEPTORS
  // ==========================================
  Future<void> onChallanDeleted({
    required PharoahManager ph,
    required String challanId,
    String? challanNo,
  }) async {
    final workingDir = await ph.getWorkingPath();
    final companyId = ph.activeCompany?.id ?? '';

    if (companyId.isNotEmpty) {
      await SyncTombstoneHub.markDeleted(
        workingDir: workingDir,
        companyId: companyId,
        id: challanId,
        referenceNo: challanNo,
      );
    }

    AppAutoSyncDaemon.instance.triggerSilentPush(ph);
  }

  Future<void> onReturnDeleted({
    required PharoahManager ph,
    required String returnId,
    String? returnNo,
  }) async {
    final workingDir = await ph.getWorkingPath();
    final companyId = ph.activeCompany?.id ?? '';

    if (companyId.isNotEmpty) {
      await SyncTombstoneHub.markDeleted(
        workingDir: workingDir,
        companyId: companyId,
        id: returnId,
        referenceNo: returnNo,
      );
    }

    AppAutoSyncDaemon.instance.triggerSilentPush(ph);
  }
}
