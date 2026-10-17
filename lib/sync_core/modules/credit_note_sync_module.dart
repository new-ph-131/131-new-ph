// FILE: lib/sync_core/modules/credit_note_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// CreditNoteSyncModule: Isolated Synchronization & Conflict Resolution Engine for Sale Returns (Credit Notes).
/// Strictly decoupled from Debit Notes, Sales, and Purchases (File Separation Rule).
class CreditNoteSyncModule {
  static const String docTypeSaleReturn = "SALE_RETURN";
  static const String docTypeCreditNote = "CREDIT_NOTE";

  /// Enqueue an Outbox mutation when a Sale Return (Credit Note) is created or modified
  static void onCreditNoteSaved(SaleReturn ret, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: ret.id,
      storeToken: storeToken,
      docType: docTypeSaleReturn,
      currentVersion: ret.version,
      isDelete: false,
      rawPayload: ret.toMap(),
    );
  }

  /// Enqueue a deletion tombstone when a Sale Return (Credit Note) is deleted
  static void onCreditNoteDeleted(SaleReturn ret, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    ret.isDeleted = 1;
    ret.status = "Cancelled";
    ret.version += 1;
    ret.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(
      syncId: ret.id,
      storeToken: storeToken,
      docType: docTypeSaleReturn,
      currentVersion: ret.version,
      isDelete: true,
      rawPayload: ret.toMap(),
    );
  }

  /// Merge incoming real-time SyncEnvelope into local Sale Return list
  static bool mergeIncomingCreditNoteEnvelope(List<SaleReturn> currentList, SyncEnvelope envelope) {
    if (envelope.documentType != docTypeSaleReturn && envelope.documentType != docTypeCreditNote) {
      return false;
    }
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incoming = SaleReturn.fromMap(envelope.billData);
    incoming.id = targetId;
    incoming.version = envelope.version;
    incoming.updatedAt = envelope.updatedAt;
    incoming.isDeleted = envelope.isDeleted;
    return applyCreditNoteMutation(currentList, incoming);
  }

  /// Apply mutation with Monotonic Versioning and LWW Clock Auditing
  static bool applyCreditNoteMutation(List<SaleReturn> currentList, SaleReturn incoming) {
    final cleanBNo = incoming.billNo.trim().toUpperCase();
    final idx = currentList.indexWhere((r) =>
        r.id == incoming.id ||
        (cleanBNo.isNotEmpty && r.billNo.trim().toUpperCase() == cleanBNo));

    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentList[idx];
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
          currentList.removeAt(idx);
          debugPrint("🗑️ [CreditNoteSyncModule] Evicted deleted credit note: ${incoming.billNo}");
          return true;
        }
      }
      return false;
    }

    if (idx != -1) {
      final local = currentList[idx];
      if (incoming.version <= local.version && incoming.updatedAt < local.updatedAt) {
        return false;
      }
      currentList[idx] = incoming;
      return true;
    } else {
      currentList.insert(0, incoming);
      return true;
    }
  }
}
