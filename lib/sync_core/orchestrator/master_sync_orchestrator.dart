// FILE: lib/sync_core/orchestrator/master_sync_orchestrator.dart
import 'package:flutter/foundation.dart';
import '../d1_sales_ledger_service.dart';
import '../models/sync_envelope.dart';
import '../modules/sales_sync_module.dart';
import '../modules/purchase_sync_module.dart';
import '../modules/sale_challan_sync_module.dart';
import '../modules/purchase_challan_sync_module.dart';
import '../modules/challan_sync_module.dart';
import '../modules/returns_sync_module.dart';
import '../modules/credit_note_sync_module.dart';
import '../modules/debit_note_sync_module.dart';
import '../modules/voucher_sync_module.dart';
import '../modules/party_sync_module.dart';
import '../../inventory_logic_center.dart';
import '../../pharoah_manager.dart';
import '../../web_live_sync/pharoah_web_manager.dart';
import '../../web_live_sync/sync_protocol/tombstone_engine.dart';

/// MasterSyncOrchestrator: Combined routing facade merging all domain modules.
/// Complies with Enterprise File Separation Architecture: Sales, Purchases, Challans,
/// Returns, and Vouchers each reside in their own clean, isolated file, and this orchestrator
/// routes and merges them dynamically upon incoming sync batches.
class MasterSyncOrchestrator {
  static final MasterSyncOrchestrator instance = MasterSyncOrchestrator._internal();
  MasterSyncOrchestrator._internal();

  /// Dispatches an individual SyncEnvelope to the appropriate domain module
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
          final sBill = envelope.billData;
          final String sBNo = (sBill['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, sBNo);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (sBNo.isNotEmpty) sBNo]);
            }
            // 🔄 Cross-Platform Revert: linked challans back to Pending
            final Set<String> targetCids = {};
            final rawLinks = sBill['linkedChallanIds'];
            if (rawLinks is List) {
              for (var l in rawLinks) {
                if (l != null && l.toString().trim().isNotEmpty) targetCids.add(l.toString().trim().toUpperCase());
              }
            }
            try {
              final loc = phApp.sales.firstWhere((s) => s.id == envelope.syncId || (sBNo.isNotEmpty && s.billNo.trim().toUpperCase() == sBNo));
              for (var l in loc.linkedChallanIds) {
                if (l.trim().isNotEmpty) targetCids.add(l.trim().toUpperCase());
              }
              for (var it in loc.items) {
                if (it.sourceChallanNo.trim().isNotEmpty) targetCids.add(it.sourceChallanNo.trim().toUpperCase());
                if (it.sourceChallanId.trim().isNotEmpty) targetCids.add(it.sourceChallanId.trim().toUpperCase());
              }
            } catch (_) {}
            if (targetCids.isNotEmpty) {
              for (var c in phApp.saleChallans) {
                if (targetCids.contains(c.id.trim().toUpperCase()) || targetCids.contains(c.billNo.trim().toUpperCase())) {
                  c.status = 'Pending';
                  c.version += 1;
                  c.updatedAt = envelope.updatedAt > 0 ? envelope.updatedAt : DateTime.now().millisecondsSinceEpoch;
                  D1SalesLedgerService.unmarkPermanentlyDeleted(c.id, c.billNo);
                  if (phApp.activeCompany != null) {
                    TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: c.id, secondaryKey: c.billNo);
                  }
                }
              }
              phApp.save();
              phApp.notifyListeners();
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, sBNo);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: envelope.syncId, secondaryKey: sBNo);
            }
          }
          mutated = SalesSyncModule.mergeIncomingSaleEnvelope(phApp.sales, envelope);
          break;
        case 'PURCHASE':
          final billData = envelope.billData;
          final String bNo = (billData['billNo'] ?? '').toString().trim().toUpperCase();
          final String pId = (billData['partyId'] ?? '').toString().trim().toUpperCase();
          final String iNo = (billData['internalNo'] ?? '').toString().trim().toUpperCase();
          final String comp2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
          final String comp3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo);
            if (phApp.activeCompany != null) {
              final delKeys = [
                envelope.syncId,
                if (iNo.isNotEmpty) iNo,
                if (comp2.isNotEmpty) comp2,
                if (comp3.isNotEmpty) comp3,
              ];
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, delKeys);
            }
            // 🔄 Cross-Platform Revert: linked purchase challans back to Pending
            final Set<String> targetPurCids = {};
            final rawPurLinks = billData['linkedChallanIds'];
            if (rawPurLinks is List) {
              for (var l in rawPurLinks) {
                if (l != null && l.toString().trim().isNotEmpty) targetPurCids.add(l.toString().trim().toUpperCase());
              }
            }
            try {
              final loc = phApp.purchases.firstWhere((p) => p.id == envelope.syncId || (iNo.isNotEmpty && p.internalNo.trim().toUpperCase() == iNo));
              for (var l in loc.linkedChallanIds) {
                if (l.trim().isNotEmpty) targetPurCids.add(l.trim().toUpperCase());
              }
              for (var it in loc.items) {
                if (it.sourceChallanNo.trim().isNotEmpty) targetPurCids.add(it.sourceChallanNo.trim().toUpperCase());
                if (it.sourceChallanId.trim().isNotEmpty) targetPurCids.add(it.sourceChallanId.trim().toUpperCase());
              }
            } catch (_) {}
            if (targetPurCids.isNotEmpty) {
              for (var c in phApp.purchaseChallans) {
                if (targetPurCids.contains(c.id.trim().toUpperCase()) || targetPurCids.contains(c.internalNo.trim().toUpperCase()) || targetPurCids.contains(c.billNo.trim().toUpperCase())) {
                  c.status = 'Pending';
                  c.version += 1;
                  c.updatedAt = envelope.updatedAt > 0 ? envelope.updatedAt : DateTime.now().millisecondsSinceEpoch;
                }
              }
              phApp.save();
              phApp.notifyListeners();
            }
          } else {
            D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo);
            if (phApp.activeCompany != null) {
              final cid = phApp.activeCompany!.id;
              TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: envelope.syncId, secondaryKey: comp3.isNotEmpty ? comp3 : comp2);
              if (iNo.isNotEmpty) TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: iNo);
              if (comp2.isNotEmpty) TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: comp2);
              if (bNo.isNotEmpty) TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: bNo);
            }
          }
          mutated = PurchaseSyncModule.mergeIncomingPurchaseEnvelope(phApp.purchases, envelope);
          break;
        case 'CHALLAN':
        case 'SALE_CHALLAN':
          final bNo = (envelope.billData['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, bNo);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (bNo.isNotEmpty) bNo]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: envelope.syncId, secondaryKey: bNo);
            }
          }
          mutated = SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope(phApp.saleChallans, envelope);
          break;
        case 'PURCHASE_CHALLAN':
          final pBill = envelope.billData;
          final iNo = (pBill['internalNo'] ?? '').toString().trim().toUpperCase();
          final bNo = (pBill['billNo'] ?? '').toString().trim().toUpperCase();
          final pId = (pBill['partyId'] ?? '').toString().trim().toUpperCase();
          final comp2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
          final comp3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [
                envelope.syncId,
                if (iNo.isNotEmpty) iNo,
                if (comp2.isNotEmpty) comp2,
                if (comp3.isNotEmpty) comp3,
              ]);
            }
          } else {
            D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo);
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo, iNo);
            if (phApp.activeCompany != null) {
              final cid = phApp.activeCompany!.id;
              TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: envelope.syncId, secondaryKey: comp3.isNotEmpty ? comp3 : comp2);
              if (iNo.isNotEmpty) TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: iNo);
              if (comp2.isNotEmpty) TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: comp2);
              if (bNo.isNotEmpty) TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: bNo);
            }
          }
          mutated = PurchaseChallanSyncModule.mergeIncomingPurchaseChallanEnvelope(phApp.purchaseChallans, envelope);
          break;
        case 'SALE_RETURN':
        case 'CREDIT_NOTE':
          final bNo = (envelope.billData['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, bNo);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (bNo.isNotEmpty) bNo]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: envelope.syncId, secondaryKey: bNo);
            }
          }
          mutated = CreditNoteSyncModule.mergeIncomingCreditNoteEnvelope(phApp.saleReturns, envelope);
          break;
        case 'PURCHASE_RETURN':
        case 'DEBIT_NOTE':
          final bNo = (envelope.billData['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, bNo);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (bNo.isNotEmpty) bNo]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: envelope.syncId, secondaryKey: bNo);
            }
          }
          mutated = DebitNoteSyncModule.mergeIncomingDebitNoteEnvelope(phApp.purchaseReturns, envelope);
          break;
        case 'PARTY':
        case 'PARTY_MASTER':
          mutated = PartySyncModule.mergeIncomingPartyEnvelope(phApp.parties, envelope);
          if (mutated) {
            phApp.save();
            phApp.notifyListeners();
          }
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
          final sBill = envelope.billData;
          final String sBNo = (sBill['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            // 🔄 Cross-Platform Revert: Find linked challan IDs BEFORE deleting sale from memory
            final Set<String> targetCids = {};
            final rawLinks = sBill['linkedChallanIds'];
            if (rawLinks is List) {
              for (var l in rawLinks) {
                if (l != null && l.toString().trim().isNotEmpty) targetCids.add(l.toString().trim().toUpperCase());
              }
            }
            try {
              final loc = phWeb.sales.firstWhere((s) => s.id == envelope.syncId || (sBNo.isNotEmpty && s.billNo.trim().toUpperCase() == sBNo));
              for (var l in loc.linkedChallanIds) {
                if (l.trim().isNotEmpty) targetCids.add(l.trim().toUpperCase());
              }
              for (var it in loc.items) {
                if (it.sourceChallanNo.trim().isNotEmpty) targetCids.add(it.sourceChallanNo.trim().toUpperCase());
                if (it.sourceChallanId.trim().isNotEmpty) targetCids.add(it.sourceChallanId.trim().toUpperCase());
              }
            } catch (_) {}

            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, sBNo);
            phWeb.purgeDeletedIds([envelope.syncId, if (sBNo.isNotEmpty) sBNo]);

            if (targetCids.isNotEmpty) {
              for (var c in phWeb.saleChallans) {
                if (targetCids.contains(c.id.trim().toUpperCase()) || targetCids.contains(c.billNo.trim().toUpperCase())) {
                  c.status = 'Pending';
                  c.version += 1;
                  c.updatedAt = envelope.updatedAt > 0 ? envelope.updatedAt : DateTime.now().millisecondsSinceEpoch;
                  phWeb.unmarkDeletedId(c.id, referenceNo: c.billNo);
                  D1SalesLedgerService.unmarkPermanentlyDeleted(c.id, c.billNo);
                }
              }
              phWeb.notifyListeners();
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, sBNo);
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: sBNo);
          }
          mutated = SalesSyncModule.mergeIncomingSaleEnvelope(phWeb.sales, envelope);
          break;
        case 'PURCHASE':
          final billData = envelope.billData;
          final String bNo = (billData['billNo'] ?? '').toString().trim().toUpperCase();
          final String pId = (billData['partyId'] ?? '').toString().trim().toUpperCase();
          final String iNo = (billData['internalNo'] ?? '').toString().trim().toUpperCase();
          final String comp2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
          final String comp3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo);
            final List<String> delList = [
              envelope.syncId,
              if (iNo.isNotEmpty) iNo,
              if (comp2.isNotEmpty) comp2,
              if (comp3.isNotEmpty) comp3,
            ];
            phWeb.purgeDeletedIds(delList);
            // 🔄 Cross-Platform Revert: linked purchase challans back to Pending
            final Set<String> targetPurCids = {};
            final rawPurLinks = billData['linkedChallanIds'];
            if (rawPurLinks is List) {
              for (var l in rawPurLinks) {
                if (l != null && l.toString().trim().isNotEmpty) targetPurCids.add(l.toString().trim().toUpperCase());
              }
            }
            try {
              final loc = phWeb.purchases.firstWhere((p) => p.id == envelope.syncId || (iNo.isNotEmpty && p.internalNo.trim().toUpperCase() == iNo));
              for (var l in loc.linkedChallanIds) {
                if (l.trim().isNotEmpty) targetPurCids.add(l.trim().toUpperCase());
              }
              for (var it in loc.items) {
                if (it.sourceChallanNo.trim().isNotEmpty) targetPurCids.add(it.sourceChallanNo.trim().toUpperCase());
                if (it.sourceChallanId.trim().isNotEmpty) targetPurCids.add(it.sourceChallanId.trim().toUpperCase());
              }
            } catch (_) {}
            if (targetPurCids.isNotEmpty) {
              for (var c in phWeb.purchaseChallans) {
                if (targetPurCids.contains(c.id.trim().toUpperCase()) || targetPurCids.contains(c.internalNo.trim().toUpperCase()) || targetPurCids.contains(c.billNo.trim().toUpperCase())) {
                  c.status = 'Pending';
                  c.version += 1;
                  c.updatedAt = envelope.updatedAt > 0 ? envelope.updatedAt : DateTime.now().millisecondsSinceEpoch;
                }
              }
              phWeb.notifyListeners();
            }
          } else {
            D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo);
            final List<String> unmList = [
              envelope.syncId,
              if (iNo.isNotEmpty) iNo,
              if (bNo.isNotEmpty) bNo,
              if (comp2.isNotEmpty) comp2,
              if (comp3.isNotEmpty) comp3,
            ];
            for (final k in unmList) {
              phWeb.deletedRecordIds.remove(k);
              phWeb.deletedRecordIds.remove(k.toUpperCase());
              phWeb.localTombstoneRegistry.remove(k);
              phWeb.localTombstoneRegistry.remove(k.toUpperCase());
              phWeb.unmarkedRecordIds.add(k);
              phWeb.unmarkedRecordIds.add(k.toUpperCase());
            }
          }
          mutated = PurchaseSyncModule.mergeIncomingPurchaseEnvelope(phWeb.purchases, envelope);
          break;
        case 'CHALLAN':
        case 'SALE_CHALLAN':
          final bNo = (envelope.billData['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            phWeb.purgeDeletedIds([envelope.syncId, if (bNo.isNotEmpty) bNo]);
          } else {
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: bNo);
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo);
          }
          mutated = SaleChallanSyncModule.mergeIncomingSaleChallanEnvelope(phWeb.saleChallans, envelope);
          break;
        case 'PURCHASE_CHALLAN':
          final pBill = envelope.billData;
          final iNo = (pBill['internalNo'] ?? '').toString().trim().toUpperCase();
          final bNo = (pBill['billNo'] ?? '').toString().trim().toUpperCase();
          final pId = (pBill['partyId'] ?? '').toString().trim().toUpperCase();
          final comp2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
          final comp3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo);
            phWeb.purgeDeletedIds([
              envelope.syncId,
              if (iNo.isNotEmpty) iNo,
              if (comp2.isNotEmpty) comp2,
              if (comp3.isNotEmpty) comp3,
            ]);
          } else {
            D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo);
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo, iNo);
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: iNo);
            if (bNo.isNotEmpty) phWeb.unmarkDeletedId(bNo);
            if (comp2.isNotEmpty) phWeb.unmarkDeletedId(comp2);
            if (comp3.isNotEmpty) phWeb.unmarkDeletedId(comp3);
          }
          mutated = PurchaseChallanSyncModule.mergeIncomingPurchaseChallanEnvelope(phWeb.purchaseChallans, envelope);
          break;
        case 'SALE_RETURN':
        case 'CREDIT_NOTE':
          final bNo = (envelope.billData['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            phWeb.purgeDeletedIds([envelope.syncId, if (bNo.isNotEmpty) bNo]);
          } else {
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: bNo);
          }
          mutated = CreditNoteSyncModule.mergeIncomingCreditNoteEnvelope(phWeb.saleReturns, envelope);
          break;
        case 'PURCHASE_RETURN':
        case 'DEBIT_NOTE':
          final bNo = (envelope.billData['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            phWeb.purgeDeletedIds([envelope.syncId, if (bNo.isNotEmpty) bNo]);
          } else {
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: bNo);
          }
          mutated = DebitNoteSyncModule.mergeIncomingDebitNoteEnvelope(phWeb.purchaseReturns, envelope);
          break;
        case 'PARTY':
        case 'PARTY_MASTER':
          mutated = PartySyncModule.mergeIncomingPartyEnvelope(phWeb.parties, envelope);
          if (mutated) {
            phWeb.notifyListeners();
          }
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

  /// Processes a complete JSON Batch payload
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
        InventoryLogicCenter.rebuildAllInventory(
          medicines: phApp.medicines,
          batchHistory: phApp.batchHistory,
          purchases: phApp.purchases,
          sales: phApp.sales,
          saleReturns: phApp.saleReturns,
          purchaseReturns: phApp.purchaseReturns,
        );
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
