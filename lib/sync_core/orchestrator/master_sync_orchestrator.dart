// FILE: lib/sync_core/orchestrator/master_sync_orchestrator.dart
import 'package:flutter/foundation.dart';
import '../models/sync_envelope.dart';
import '../modules/sales_sync_module.dart';
import '../modules/purchase_sync_module.dart';
import '../modules/challan_sync_module.dart';
import '../modules/voucher_sync_module.dart';
import '../../pharoah_manager.dart';
import '../../web_live_sync/pharoah_web_manager.dart';

/// MasterSyncOrchestrator: Combined routing facade merging all domain modules.
/// Complies with the File Separation Rule: Sales, Purchases, Challans, and Vouchers
/// each reside in their own clean, isolated file, and this orchestrator merges them
/// dynamically upon incoming sync batches.
class MasterSyncOrchestrator {
  static final MasterSyncOrchestrator instance = MasterSyncOrchestrator._internal();
  MasterSyncOrchestrator._internal();

  /// Dispatches an individual SyncEnvelope to the appropriate module
  static bool dispatchEnvelope({
    required SyncEnvelope envelope,
    PharoahManager? phApp,
    PharoahWebManager? phWeb,
  }) {
    final docType = envelope.documentType.toUpperCase().trim();
    bool mutated = false;

    if (phApp != null) {
      switch (docType) {
        case 'SALE':
          mutated = SalesSyncModule.mergeIncomingSaleEnvelope(phApp.sales, envelope);
          break;
        case 'PURCHASE':
          mutated = PurchaseSyncModule.mergeIncomingPurchaseEnvelope(phApp.purchases, envelope);
          break;
        case 'CHALLAN':
          mutated = ChallanSyncModule.mergeIncomingChallanEnvelope(phApp.saleChallans, envelope);
          break;
        case 'VOUCHER':
          mutated = VoucherSyncModule.mergeIncomingVoucherEnvelope(phApp.vouchers, envelope);
          break;
        default:
          debugPrint("⚠ [MasterSyncOrchestrator] Unknown document type: $docType");
      }
    }

    if (phWeb != null) {
      switch (docType) {
        case 'SALE':
          mutated = SalesSyncModule.mergeIncomingSaleEnvelope(phWeb.sales, envelope);
          break;
        case 'PURCHASE':
          mutated = PurchaseSyncModule.mergeIncomingPurchaseEnvelope(phWeb.purchases, envelope);
          break;
        case 'CHALLAN':
          mutated = ChallanSyncModule.mergeIncomingChallanEnvelope(phWeb.saleChallans, envelope);
          break;
        case 'VOUCHER':
          mutated = VoucherSyncModule.mergeIncomingVoucherEnvelope(phWeb.vouchers, envelope);
          break;
        default:
          debugPrint("⚠ [MasterSyncOrchestrator] Unknown document type: $docType");
      }
    }

    return mutated;
  }

  /// Processes a complete Step 4 JSON Batch payload
  static int dispatchBatchOperations({
    required List<dynamic> operations,
    PharoahManager? phApp,
    PharoahWebManager? phWeb,
  }) {
    if (operations.isEmpty) return 0;
    int appliedCount = 0;

    for (final rawOp in operations) {
      try {
        final Map<String, dynamic> opMap = rawOp is Map<String, dynamic>
            ? rawOp
            : Map<String, dynamic>.from(rawOp as Map);

        final envelope = SyncEnvelope.fromMap(opMap);
        final success = dispatchEnvelope(envelope: envelope, phApp: phApp, phWeb: phWeb);
        if (success) appliedCount++;
      } catch (e) {
        debugPrint("⚠ [MasterSyncOrchestrator] Failed to apply operation: $e");
      }
    }

    if (appliedCount > 0) {
      if (phApp != null) {
        phApp.save();
        phApp.notifyListeners();
      }
      if (phWeb != null) {
        phWeb.rebuildInventory();
        phWeb.notifyListeners();
      }
      debugPrint("🚀 [MasterSyncOrchestrator] Applied $appliedCount mutations from JSON batch!");
    }

    return appliedCount;
  }
}
