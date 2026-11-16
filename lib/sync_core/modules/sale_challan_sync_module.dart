// FILE: lib/sync_core/modules/sale_challan_sync_module.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// SaleChallanSyncModule: Isolated Synchronization & Conflict Resolution Engine for Sale Challans (Dispatch Notes).
/// Strictly decoupled from Purchase Challan, Sales, and Purchases (File Separation Rule).
class SaleChallanSyncModule {
  static const String docTypeSaleChallan = "SALE_CHALLAN";

  static int statusRank(String s) {
    final u = s.trim().toUpperCase();
    if (u == "BILLED") return 3;
    if (u == "CANCELLED") return 2;
    return 1;
  }

  /// Enqueue an Outbox mutation when a Sale Challan is created or modified
  static void onSaleChallanSaved(SaleChallan challan, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: challan.id,
      storeToken: storeToken,
      docType: docTypeSaleChallan,
      currentVersion: challan.version,
      isDelete: false,
      rawPayload: challan.toMap(),
      exactVersion: true,
    );
  }

  /// Enqueue a mutation when a Sale Challan is Cancelled (Middle-Challan Cancel)
  static void onSaleChallanCancelled(SaleChallan challan, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    challan.isDeleted = 0;
    challan.status = "Cancelled";
    challan.version += 1;
    challan.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(
      syncId: challan.id,
      storeToken: storeToken,
      docType: docTypeSaleChallan,
      currentVersion: challan.version,
      isDelete: false,
      rawPayload: challan.toMap(),
      exactVersion: true,
    );
  }

  /// Enqueue a deletion tombstone when a Sale Challan is hard deleted (Last-Draft Delete)
  static void onSaleChallanDeleted(SaleChallan challan, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    challan.isDeleted = 1;
    challan.status = "Deleted";
    challan.version += 1;
    challan.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(
      syncId: challan.id,
      storeToken: storeToken,
      docType: docTypeSaleChallan,
      currentVersion: challan.version,
      isDelete: true,
      rawPayload: challan.toMap(),
      exactVersion: true,
    );
  }

  /// Merge incoming real-time SyncEnvelope into local Sale Challan list
  static bool mergeIncomingSaleChallanEnvelope(List<SaleChallan> currentChallans, SyncEnvelope envelope) {
    if (envelope.documentType != docTypeSaleChallan && envelope.documentType != "CHALLAN") return false;
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;

    final incomingChallan = SaleChallan.fromMap(envelope.billData);
    incomingChallan.id = targetId;
    incomingChallan.version = envelope.version;
    incomingChallan.updatedAt = envelope.updatedAt;
    incomingChallan.isDeleted = envelope.isDeleted;

    return applySaleChallanMutation(currentChallans, incomingChallan);
  }

  /// Apply mutation with Monotonic Versioning, Status Rank and LWW Clock Auditing
  static bool applySaleChallanMutation(List<SaleChallan> currentChallans, SaleChallan incoming) {
    final idx = currentChallans.indexWhere((c) => c.id.trim().isNotEmpty && incoming.id.trim().isNotEmpty && c.id.trim() == incoming.id.trim());

    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentChallans[idx];
        if (local.status == "Billed") return false;
        if (incoming.version > local.version || (incoming.version == local.version && incoming.updatedAt >= local.updatedAt)) {
          currentChallans.removeAt(idx);
          debugPrint("🗑️ [SaleChallanSyncModule] Evicted deleted sale challan: ${incoming.billNo}");
          return true;
        }
      }
      return false;
    }

    if (idx > -1) {
      final local = currentChallans[idx];
      // 🛡️ Strict Monotonic Versioning + LWW Clock Auditing (#F-06 Deterministic Equal-Ver/Equal-Ts)
      if (incoming.version < local.version) return false;
      if (incoming.version == local.version) {
        if (incoming.updatedAt < local.updatedAt) return false;
        if (incoming.updatedAt == local.updatedAt) {
          final int localRank = statusRank(local.status);
          final int incomingRank = statusRank(incoming.status);
          if (localRank != incomingRank) {
            if (incomingRank < localRank) return false;
          } else {
            final String localCanon = _canonicalDigest(local);
            final String incomingCanon = _canonicalDigest(incoming);
            if (localCanon == incomingCanon) return false;
            if (incomingCanon.compareTo(localCanon) <= 0) return false;
          }
        }
      }

      // Never silently demote Billed to Pending unless version is higher
      if (local.status.trim().toUpperCase() == "BILLED" &&
          incoming.status.trim().toUpperCase() != "BILLED" &&
          incoming.version <= local.version) {
        return false;
      }

      if (incoming.status == "Billed" && incoming.billedInvoiceNo.isEmpty && local.billedInvoiceNo.isNotEmpty) {
        incoming.billedInFy = local.billedInFy;
        incoming.billedInvoiceId = local.billedInvoiceId;
        incoming.billedInvoiceNo = local.billedInvoiceNo;
        incoming.billedDate = local.billedDate;
      }
      currentChallans[idx] = incoming;
      return true;
    } else {
      // 🛡️ PRIMARY ID RULE: Never match/overwrite if incoming has a non-empty ID that did not match
      int billNoIdx = (incoming.id.trim().isEmpty && incoming.billNo.isNotEmpty)
          ? currentChallans.indexWhere((c) => c.id.trim().isEmpty && c.billNo.trim() == incoming.billNo.trim() && c.effectiveOriginalFy == incoming.effectiveOriginalFy)
          : -1;
      if (billNoIdx != -1) {
        final existing = currentChallans[billNoIdx];
        if (incoming.version > existing.version || (incoming.version == existing.version && incoming.updatedAt >= existing.updatedAt)) {
          currentChallans[billNoIdx] = incoming;
          return true;
        }
        return false;
      } else {
        currentChallans.insert(0, incoming);
        return true;
      }
    }
  }

  static String _canonicalDigest(SaleChallan c) {
    return jsonEncode({
      'id': c.id.trim(),
      'billNo': c.billNo.trim(),
      'partyId': c.partyId.trim(),
      'partyName': c.partyName.trim(),
      'status': c.status.trim(),
      'totalAmount': c.totalAmount,
      'date': c.date.toIso8601String(),
      'originalFy': c.effectiveOriginalFy,
      'billedInFy': c.billedInFy.trim(),
      'billedInvoiceId': c.billedInvoiceId.trim(),
      'billedInvoiceNo': c.billedInvoiceNo.trim(),
      'billedDate': c.billedDate.trim(),
      'remarks': c.remarks.trim(),
      'isDeleted': c.isDeleted,
      'isSigned': c.isSigned,
      'items': c.items.map((i) => i.toMap()).toList(),
    });
  }
}
