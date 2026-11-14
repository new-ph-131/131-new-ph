import '../../logic/app_settings_model.dart';
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
import '../modules/medicine_sync_module.dart';
import '../modules/batch_sync_module.dart';
import '../modules/company_sync_module.dart';
import '../modules/salt_sync_module.dart';
import '../modules/route_sync_module.dart';
import '../modules/gst_diary_sync_module.dart';
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
  static const Set<String> _fyScopedTransactionTypes = {
    'SALE',
    'PURCHASE',
    'CHALLAN',
    'SALE_CHALLAN',
    'PURCHASE_CHALLAN',
    'RETURN',
    'SALE_RETURN',
    'CREDIT_NOTE',
    'PURCHASE_RETURN',
    'DEBIT_NOTE',
    'VOUCHER',
    'GST_DIARY_SESSION',
    'GST_SESSION',
  };

  static DateTime? _extractEnvelopeDate(Map<String, dynamic> data) {
    final raw = data['date'] ?? data['fromDate'] ?? data['billDate'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }

  static bool dispatchEnvelope({
    required SyncEnvelope envelope,
    PharoahManager? phApp,
    PharoahWebManager? phWeb,
  }) {
    final docType = envelope.documentType.toUpperCase().trim();
    final String targetFy = (phApp != null ? phApp.currentFY : (phWeb != null ? phWeb.financialYear : D1SalesLedgerService.activeFinancialYear)).trim();
    if (_fyScopedTransactionTypes.contains(docType)) {
      final DateTime? envDate = _extractEnvelopeDate(envelope.billData);
      if (!D1SalesLedgerService.doesEventBelongToActiveFY(envelope.billData, envDate, targetFy)) {
        // Pending Challans carry forward across FYs
        final String status = (envelope.billData['status'] ?? '').toString();
        final bool isPendingChallan = (docType == 'CHALLAN' || docType == 'SALE_CHALLAN' || docType == 'PURCHASE_CHALLAN') && status == 'Pending';
        if (!isPendingChallan) {
          return false;
        }
      }
    }
    bool mutated = false;

    if (phApp != null) {
      switch (docType) {
        case 'SALE':
          final sBill = envelope.billData;
          final String sBNo = (sBill['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, sBNo, "", targetFy);
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
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, sBNo, "", targetFy);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: envelope.syncId, secondaryKey: sBNo);
            }
          }
          mutated = SalesSyncModule.mergeIncomingSaleEnvelope(phApp.sales, envelope);
          break;
        case 'PURCHASE':
          final billData = envelope.billData;
          final String bNo = (billData['billNo'] ?? '').toString().trim();
          final String pId = (billData['partyId'] ?? '').toString().trim().toUpperCase();
          final String iNo = (billData['internalNo'] ?? '').toString().trim().toUpperCase();
          final String comp2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
          final String comp3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
          final String comp2Upper = comp2.isNotEmpty ? comp2.toUpperCase() : "";
          final String comp3Upper = comp3.isNotEmpty ? comp3.toUpperCase() : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo, targetFy);
            if (phApp.activeCompany != null) {
              final delKeys = [
                envelope.syncId,
                if (iNo.isNotEmpty) iNo,
                if (comp2.isNotEmpty) comp2,
                if (comp3.isNotEmpty) comp3,
                if (comp2Upper.isNotEmpty && comp2Upper != comp2) comp2Upper,
                if (comp3Upper.isNotEmpty && comp3Upper != comp3) comp3Upper,
              ];
              TombstoneEngine.recordBatchTombstones(
                phApp.activeCompany!.id,
                delKeys,
                timestamp: envelope.updatedAt > 0 ? envelope.updatedAt : null,
                fy: targetFy,
              );
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
            if (D1SalesLedgerService.isPurchaseDeleted(envelope.syncId, pId, bNo, iNo, targetFy)) {
              break;
            }
            int knownVer = D1SalesLedgerService.getPurchaseKnownVersion(envelope.syncId, pId, bNo, iNo, targetFy);
            int localUpd = 0;
            for (final p in phApp.purchases) {
              if (p.id == envelope.syncId || (iNo.isNotEmpty && p.internalNo.trim().toUpperCase() == iNo)) {
                if (p.version > knownVer) knownVer = p.version;
                if (p.updatedAt > localUpd) localUpd = p.updatedAt;
              }
            }
            if (envelope.version < knownVer && (envelope.updatedAt == 0 || envelope.updatedAt < localUpd)) {
              break;
            }
            D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo, targetFy);
            if (phApp.activeCompany != null) {
              final cid = phApp.activeCompany!.id;
              TombstoneEngine.unmarkTombstoneWithTimestamp(
                cid,
                id: envelope.syncId,
                secondaryKey: comp3.isNotEmpty ? comp3 : comp2,
                fy: targetFy,
              );
              if (iNo.isNotEmpty) TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: iNo, fy: targetFy);
              if (comp2.isNotEmpty) TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: comp2, fy: targetFy);
              if (comp2Upper.isNotEmpty && comp2Upper != comp2) TombstoneEngine.unmarkTombstoneWithTimestamp(cid, id: comp2Upper, fy: targetFy);
            }
          }
          mutated = PurchaseSyncModule.mergeIncomingPurchaseEnvelope(phApp.purchases, envelope, fy: targetFy);
          break;
        case 'CHALLAN':
        case 'SALE_CHALLAN':
          final bNo = (envelope.billData['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, bNo, "", targetFy);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (bNo.isNotEmpty) bNo]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo, "", targetFy);
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
            D1SalesLedgerService.markPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo, targetFy);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [
                envelope.syncId,
                if (iNo.isNotEmpty) iNo,
                if (comp2.isNotEmpty) comp2,
                if (comp3.isNotEmpty) comp3,
              ]);
            }
          } else {
            D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo, targetFy);
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
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, bNo, "", targetFy);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (bNo.isNotEmpty) bNo]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo, "", targetFy);
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
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, bNo, "", targetFy);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (bNo.isNotEmpty) bNo]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo, "", targetFy);
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
        case 'MEDICINE':
        case 'ITEM':
        case 'PRODUCT':
          mutated = MedicineSyncModule.mergeIncomingMedicineEnvelope(phApp.medicines, envelope);
          if (mutated) {
            phApp.save();
            phApp.notifyListeners();
          }
          break;
        case 'VOUCHER':
          final vMap = envelope.billData;
          final String vNo = (vMap['voucherNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, vNo, "", targetFy);
            if (phApp.activeCompany != null) {
              final List<String> tKeys = [envelope.syncId, if (vNo.isNotEmpty) vNo];
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, tKeys);
            }
            final int beforeLen = phApp.vouchers.length;
            phApp.vouchers.removeWhere((v) =>
              v.id == envelope.syncId ||
              (vNo.isNotEmpty && v.voucherNo.trim().toUpperCase() == vNo)
            );
            mutated = phApp.vouchers.length != beforeLen;
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, vNo, "", targetFy);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: envelope.syncId, secondaryKey: vNo);
            }
            mutated = VoucherSyncModule.mergeIncomingVoucherEnvelope(phApp.vouchers, envelope);
          }
          if (mutated) {
            phApp.save();
            phApp.notifyListeners();
          }
          break;
        case 'BATCH':
          final bData = envelope.billData;
          final String medKey = (bData['medKey'] ?? '').toString().trim();
          final dynamic rawBatch = bData['batch'];
          final String rawBNo = (rawBatch is Map ? (rawBatch['batch'] ?? '') : '').toString().trim();
          final String bNo = rawBNo.toUpperCase();
          final String batchExp = (rawBatch is Map ? (rawBatch['exp'] ?? '') : '').toString().trim();
          final double batchMrp = double.tryParse((rawBatch is Map ? rawBatch['mrp'] : 0)?.toString() ?? '0') ?? 0.0;
          final double batchPurRate = double.tryParse((rawBatch is Map ? rawBatch['purchaseRate'] : 0)?.toString() ?? '0') ?? 0.0;
          final String canonicalSyncId = BatchSyncModule.getBatchSyncId(
            medKey,
            rawBNo,
            exp: batchExp,
            mrp: batchMrp,
            purRate: batchPurRate,
          );
          final String batchEnvFy = (bData['fy'] ?? (rawBatch is Map ? rawBatch['fy'] : '') ?? '').toString().trim();
          if (batchEnvFy.isNotEmpty && targetFy.isNotEmpty && batchEnvFy != targetFy &&
              (envelope.isDeleted == 1 || envelope.action == 'DELETE')) {
            break;
          }
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, bNo, medKey, targetFy);
            if (canonicalSyncId != envelope.syncId) {
              D1SalesLedgerService.markPermanentlyDeleted(canonicalSyncId, bNo, medKey, targetFy);
            }
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(
                phApp.activeCompany!.id,
                [
                  envelope.syncId,
                  if (canonicalSyncId != envelope.syncId) canonicalSyncId,
                  if (bNo.isNotEmpty) bNo,
                ],
                fy: targetFy,
              );
            }
            if (phApp.batchHistory.containsKey(medKey)) {
              final list = phApp.batchHistory[medKey]!;
              final beforeLen = list.length;
              if (bNo.isNotEmpty) {
                list.removeWhere((b) => b.batch.trim().toUpperCase() == bNo);
              } else {
                final int matchIdx = InventoryLogicCenter.findMatchingBatchIndex(
                  list,
                  batchNo: rawBNo,
                  exp: batchExp,
                  mrp: batchMrp,
                  purRate: batchPurRate,
                  exactEmptyBatchLot: true,
                );
                if (matchIdx != -1) {
                  list.removeAt(matchIdx);
                } else {
                  list.removeWhere((b) =>
                      b.batch.trim().isEmpty &&
                      BatchSyncModule.getBatchSyncId(
                        medKey,
                        b.batch,
                        exp: b.exp,
                        mrp: b.mrp,
                        purRate: b.purRate,
                      ) == envelope.syncId);
                }
              }
              mutated = list.length != beforeLen;
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo, medKey, targetFy);
            if (canonicalSyncId != envelope.syncId) {
              D1SalesLedgerService.unmarkPermanentlyDeleted(canonicalSyncId, bNo, medKey, targetFy);
            }
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(
                phApp.activeCompany!.id,
                id: envelope.syncId,
                secondaryKey: bNo.isNotEmpty ? bNo : null,
                fy: targetFy,
              );
            }
            mutated = BatchSyncModule.mergeIncomingBatchEnvelope(phApp.batchHistory, envelope);
          }
          if (mutated) {
            InventoryLogicCenter.rebuildAllInventory(
              medicines: phApp.medicines,
              batchHistory: phApp.batchHistory,
              purchases: phApp.purchases,
              sales: phApp.sales,
              saleReturns: phApp.saleReturns,
              purchaseReturns: phApp.purchaseReturns,
            );
            phApp.save();
            phApp.notifyListeners();
          }
          break;
        case 'CONFIG':
        case 'APP_CONFIG':
          final incomingCfg = AppConfig.fromMap(envelope.billData);
          if (phApp.config.updatedAt == 0 ||
              incomingCfg.updatedAt >= phApp.config.updatedAt ||
              incomingCfg.version >= phApp.config.version) {
            phApp.config = incomingCfg;
            mutated = true;
            phApp.save();
            phApp.notifyListeners();
          }
          break;
        case 'COMPANY':
          final String cName = (envelope.billData['name'] ?? '').toString().trim().toUpperCase();
          final String cKey = cName.isNotEmpty ? "COMP_${CompanySyncModule.cleanString(cName)}" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, cKey);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (cKey.isNotEmpty) cKey]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, cKey);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: envelope.syncId, secondaryKey: cKey);
            }
          }
          mutated = CompanySyncModule.mergeIncomingCompanyEnvelope(
            phApp.companies,
            envelope,
            medicines: phApp.medicines,
            shortages: phApp.shortages,
          );
          if (mutated) {
            phApp.save();
            phApp.notifyListeners();
          }
          break;
        case 'SALT':
          final String sName = (envelope.billData['name'] ?? '').toString().trim().toUpperCase();
          final String sKey = sName.isNotEmpty ? "SALT_${SaltSyncModule.cleanString(sName)}" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, sKey);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (sKey.isNotEmpty) sKey]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, sKey);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: envelope.syncId, secondaryKey: sKey);
            }
          }
          mutated = SaltSyncModule.mergeIncomingSaltEnvelope(
            phApp.salts,
            envelope,
            medicines: phApp.medicines,
          );
          if (mutated) {
            phApp.save();
            phApp.notifyListeners();
          }
          break;
        case 'ROUTE':
          final String rName = (envelope.billData['name'] ?? '').toString().trim().toUpperCase();
          final String rKey = rName.isNotEmpty ? "ROUTE_${RouteSyncModule.cleanString(rName)}" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, rKey);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [envelope.syncId, if (rKey.isNotEmpty) rKey]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, rKey);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: envelope.syncId, secondaryKey: rKey);
            }
          }
          mutated = RouteSyncModule.mergeIncomingRouteEnvelope(
            phApp.routes,
            envelope,
            parties: phApp.parties,
          );
          if (mutated) {
            phApp.save();
            phApp.notifyListeners();
          }
          break;
        case 'GST_DIARY_SESSION':
        case 'GST_SESSION':
          final sId = (envelope.billData['id'] ?? envelope.syncId).toString().trim();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(sId, sId);
            if (phApp.activeCompany != null) {
              TombstoneEngine.recordBatchTombstones(phApp.activeCompany!.id, [sId]);
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(sId, sId);
            if (phApp.activeCompany != null) {
              TombstoneEngine.unmarkTombstoneWithTimestamp(phApp.activeCompany!.id, id: sId);
            }
          }
          mutated = GstDiarySyncModule.mergeIncomingSessionEnvelope(phApp.gstDiarySessions, envelope);
          if (mutated) {
            phApp.save();
            phApp.notifyListeners();
          }
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

            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, sBNo, "", targetFy);
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
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, sBNo, "", targetFy);
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: sBNo);
          }
          mutated = SalesSyncModule.mergeIncomingSaleEnvelope(phWeb.sales, envelope);
          break;
        case 'PURCHASE':
          final billData = envelope.billData;
          final String bNo = (billData['billNo'] ?? '').toString().trim();
          final String pId = (billData['partyId'] ?? '').toString().trim().toUpperCase();
          final String iNo = (billData['internalNo'] ?? '').toString().trim().toUpperCase();
          final String comp2 = (pId.isNotEmpty && bNo.isNotEmpty) ? "${pId}_$bNo" : "";
          final String comp3 = (pId.isNotEmpty && bNo.isNotEmpty && iNo.isNotEmpty) ? "${pId}_${bNo}_$iNo" : "";
          final String comp2Upper = comp2.isNotEmpty ? comp2.toUpperCase() : "";
          final String comp3Upper = comp3.isNotEmpty ? comp3.toUpperCase() : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo, targetFy);
            final List<String> delList = [
              envelope.syncId,
              if (iNo.isNotEmpty) iNo,
              if (comp2.isNotEmpty) comp2,
              if (comp3.isNotEmpty) comp3,
              if (comp2Upper.isNotEmpty && comp2Upper != comp2) comp2Upper,
              if (comp3Upper.isNotEmpty && comp3Upper != comp3) comp3Upper,
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
            if (D1SalesLedgerService.isPurchaseDeleted(envelope.syncId, pId, bNo, iNo, targetFy)) {
              break;
            }
            int knownVer = D1SalesLedgerService.getPurchaseKnownVersion(envelope.syncId, pId, bNo, iNo, targetFy);
            int localUpd = 0;
            for (final p in phWeb.purchases) {
              if (p.id == envelope.syncId || (iNo.isNotEmpty && p.internalNo.trim().toUpperCase() == iNo)) {
                if (p.version > knownVer) knownVer = p.version;
                if (p.updatedAt > localUpd) localUpd = p.updatedAt;
              }
            }
            if (envelope.version < knownVer && (envelope.updatedAt == 0 || envelope.updatedAt < localUpd)) {
              break;
            }
            D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo, targetFy);
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: iNo.isNotEmpty ? iNo : null);
            if (comp2.isNotEmpty) phWeb.unmarkDeletedId(comp2, preserveCase: true);
            if (comp3.isNotEmpty) phWeb.unmarkDeletedId(comp3, preserveCase: true);
          }
          mutated = PurchaseSyncModule.mergeIncomingPurchaseEnvelope(phWeb.purchases, envelope, fy: targetFy);
          break;
        case 'CHALLAN':
        case 'SALE_CHALLAN':
          final bNo = (envelope.billData['billNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            phWeb.purgeDeletedIds([envelope.syncId, if (bNo.isNotEmpty) bNo]);
          } else {
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: bNo);
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo, "", targetFy);
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
            D1SalesLedgerService.markPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo, targetFy);
            phWeb.purgeDeletedIds([
              envelope.syncId,
              if (iNo.isNotEmpty) iNo,
              if (comp2.isNotEmpty) comp2,
              if (comp3.isNotEmpty) comp3,
            ]);
          } else {
            D1SalesLedgerService.unmarkPurchasePermanentlyDeleted(envelope.syncId, pId, bNo, iNo, targetFy);
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
        case 'MEDICINE':
        case 'ITEM':
        case 'PRODUCT':
          mutated = MedicineSyncModule.mergeIncomingMedicineEnvelope(phWeb.medicines, envelope);
          if (mutated) {
            phWeb.notifyListeners();
          }
          break;
        case 'VOUCHER':
          final vMap = envelope.billData;
          final String vNo = (vMap['voucherNo'] ?? '').toString().trim().toUpperCase();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, vNo, "", targetFy);
            phWeb.purgeDeletedIds([envelope.syncId, if (vNo.isNotEmpty) vNo]);
            mutated = true;
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, vNo, "", targetFy);
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: vNo);
            mutated = VoucherSyncModule.mergeIncomingVoucherEnvelope(phWeb.vouchers, envelope);
          }
          if (mutated) {
            phWeb.notifyListeners();
          }
          break;
        case 'BATCH':
          final bData = envelope.billData;
          final String medKey = (bData['medKey'] ?? '').toString().trim();
          final dynamic rawBatch = bData['batch'];
          final String rawBNo = (rawBatch is Map ? (rawBatch['batch'] ?? '') : '').toString().trim();
          final String bNo = rawBNo.toUpperCase();
          final String batchExp = (rawBatch is Map ? (rawBatch['exp'] ?? '') : '').toString().trim();
          final double batchMrp = double.tryParse((rawBatch is Map ? rawBatch['mrp'] : 0)?.toString() ?? '0') ?? 0.0;
          final double batchPurRate = double.tryParse((rawBatch is Map ? rawBatch['purchaseRate'] : 0)?.toString() ?? '0') ?? 0.0;
          final String canonicalSyncId = BatchSyncModule.getBatchSyncId(
            medKey,
            rawBNo,
            exp: batchExp,
            mrp: batchMrp,
            purRate: batchPurRate,
          );
          final String batchEnvFy = (bData['fy'] ?? (rawBatch is Map ? rawBatch['fy'] : '') ?? '').toString().trim();
          if (batchEnvFy.isNotEmpty && targetFy.isNotEmpty && batchEnvFy != targetFy &&
              (envelope.isDeleted == 1 || envelope.action == 'DELETE')) {
            break;
          }
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, bNo, medKey, targetFy);
            if (canonicalSyncId != envelope.syncId) {
              D1SalesLedgerService.markPermanentlyDeleted(canonicalSyncId, bNo, medKey, targetFy);
            }
            phWeb.purgeDeletedIds([
              envelope.syncId,
              if (canonicalSyncId != envelope.syncId) canonicalSyncId,
              if (bNo.isNotEmpty) bNo,
            ]);
            if (phWeb.batchHistory.containsKey(medKey)) {
              final list = phWeb.batchHistory[medKey]!;
              final beforeLen = list.length;
              if (bNo.isNotEmpty) {
                list.removeWhere((b) => b.batch.trim().toUpperCase() == bNo);
              } else {
                final int matchIdx = InventoryLogicCenter.findMatchingBatchIndex(
                  list,
                  batchNo: rawBNo,
                  exp: batchExp,
                  mrp: batchMrp,
                  purRate: batchPurRate,
                  exactEmptyBatchLot: true,
                );
                if (matchIdx != -1) {
                  list.removeAt(matchIdx);
                } else {
                  list.removeWhere((b) =>
                      b.batch.trim().isEmpty &&
                      BatchSyncModule.getBatchSyncId(
                        medKey,
                        b.batch,
                        exp: b.exp,
                        mrp: b.mrp,
                        purRate: b.purRate,
                      ) == envelope.syncId);
                }
              }
              mutated = list.length != beforeLen;
            }
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, bNo, medKey, targetFy);
            if (canonicalSyncId != envelope.syncId) {
              D1SalesLedgerService.unmarkPermanentlyDeleted(canonicalSyncId, bNo, medKey, targetFy);
            }
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: bNo.isNotEmpty ? bNo : null);
            mutated = BatchSyncModule.mergeIncomingBatchEnvelope(phWeb.batchHistory, envelope);
          }
          if (mutated) {
            phWeb.rebuildInventory();
            phWeb.notifyListeners();
          }
          break;
        case 'CONFIG':
        case 'APP_CONFIG':
          final incomingCfg = AppConfig.fromMap(envelope.billData);
          if (phWeb.appConfig.updatedAt == 0 ||
              incomingCfg.updatedAt >= phWeb.appConfig.updatedAt ||
              incomingCfg.version >= phWeb.appConfig.version) {
            phWeb.appConfig = incomingCfg;
            mutated = true;
            phWeb.notifyListeners();
          }
          break;
        case 'COMPANY':
          final String cName = (envelope.billData['name'] ?? '').toString().trim().toUpperCase();
          final String cKey = cName.isNotEmpty ? "COMP_${CompanySyncModule.cleanString(cName)}" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, cKey);
            phWeb.purgeDeletedIds([envelope.syncId, if (cKey.isNotEmpty) cKey]);
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, cKey);
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: cKey);
          }
          mutated = CompanySyncModule.mergeIncomingCompanyEnvelope(
            phWeb.companies,
            envelope,
            medicines: phWeb.medicines,
            shortages: phWeb.shortages,
          );
          if (mutated) {
            phWeb.notifyListeners();
          }
          break;
        case 'SALT':
          final String sName = (envelope.billData['name'] ?? '').toString().trim().toUpperCase();
          final String sKey = sName.isNotEmpty ? "SALT_${SaltSyncModule.cleanString(sName)}" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, sKey);
            phWeb.purgeDeletedIds([envelope.syncId, if (sKey.isNotEmpty) sKey]);
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, sKey);
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: sKey);
          }
          mutated = SaltSyncModule.mergeIncomingSaltEnvelope(
            phWeb.salts,
            envelope,
            medicines: phWeb.medicines,
          );
          if (mutated) {
            phWeb.notifyListeners();
          }
          break;
        case 'ROUTE':
          final String rName = (envelope.billData['name'] ?? '').toString().trim().toUpperCase();
          final String rKey = rName.isNotEmpty ? "ROUTE_${RouteSyncModule.cleanString(rName)}" : "";
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(envelope.syncId, rKey);
            phWeb.purgeDeletedIds([envelope.syncId, if (rKey.isNotEmpty) rKey]);
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(envelope.syncId, rKey);
            phWeb.unmarkDeletedId(envelope.syncId, referenceNo: rKey);
          }
          mutated = RouteSyncModule.mergeIncomingRouteEnvelope(
            phWeb.routes,
            envelope,
            parties: phWeb.parties,
          );
          if (mutated) {
            phWeb.notifyListeners();
          }
          break;
        case 'GST_DIARY_SESSION':
        case 'GST_SESSION':
          final sId = (envelope.billData['id'] ?? envelope.syncId).toString().trim();
          if (envelope.isDeleted == 1 || envelope.action == 'DELETE') {
            D1SalesLedgerService.markPermanentlyDeleted(sId, sId);
            phWeb.purgeDeletedIds([sId]);
          } else {
            D1SalesLedgerService.unmarkPermanentlyDeleted(sId, sId);
            phWeb.unmarkDeletedId(sId);
          }
          mutated = GstDiarySyncModule.mergeIncomingSessionEnvelope(phWeb.gstDiarySessions, envelope);
          if (mutated) {
            phWeb.notifyListeners();
          }
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
        phApp.save();
        phApp.notifyListeners();
      }
      if (phWeb != null) {
        phWeb.rebuildInventory();
        phWeb.snapshotActiveFyToVault();
        phWeb.notifyListeners();
      }
      debugPrint("🚀 [MasterSyncOrchestrator] Applied $appliedCount mutations from JSON batch!");
    }
    return appliedCount;
  }
}
