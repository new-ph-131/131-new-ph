// FILE: lib/sync_core/modules/debit_note_sync_module.dart
import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// DebitNoteSyncModule: Isolated Synchronization & Conflict Resolution Engine for Purchase Returns (Debit Notes).
/// Strictly decoupled from Credit Notes, Sales, and Purchases (File Separation Rule).
class DebitNoteSyncModule {
  static const String docTypePurchaseReturn = "PURCHASE_RETURN";
  static const String docTypeDebitNote = "DEBIT_NOTE";

  /// Enqueue an Outbox mutation when a Purchase Return (Debit Note) is created or modified
  static void onDebitNoteSaved(PurchaseReturn ret, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: ret.id,
      storeToken: storeToken,
      docType: docTypePurchaseReturn,
      currentVersion: ret.version,
      isDelete: false,
      rawPayload: ret.toMap(),
    );
  }

  /// Enqueue a deletion tombstone when a Purchase Return (Debit Note) is deleted
  static void onDebitNoteDeleted(PurchaseReturn ret, String storeToken) {
    if (storeToken.trim().isEmpty) return;
    ret.isDeleted = 1;
    ret.status = "Cancelled";
    ret.version += 1;
    ret.updatedAt = DateTime.now().millisecondsSinceEpoch;
    SyncQueueManager.enqueueMutation(
      syncId: ret.id,
      storeToken: storeToken,
      docType: docTypePurchaseReturn,
      currentVersion: ret.version,
      isDelete: true,
      rawPayload: ret.toMap(),
    );
  }

  /// Merge incoming real-time SyncEnvelope into local Purchase Return list
  static bool mergeIncomingDebitNoteEnvelope(List<PurchaseReturn> currentList, SyncEnvelope envelope) {
    if (envelope.documentType != docTypePurchaseReturn && envelope.documentType != docTypeDebitNote) {
      return false;
    }
    final targetId = envelope.syncId.trim();
    if (targetId.isEmpty) return false;
    final incoming = PurchaseReturn.fromMap(envelope.billData);
    incoming.id = targetId;
    incoming.version = envelope.version;
    incoming.updatedAt = envelope.updatedAt;
    incoming.isDeleted = envelope.isDeleted;
    return applyDebitNoteMutation(currentList, incoming);
  }

  /// Apply mutation with Monotonic Versioning and LWW Clock Auditing
  static bool applyDebitNoteMutation(List<PurchaseReturn> currentList, PurchaseReturn incoming) {
    final cleanBNo = incoming.billNo.trim().toUpperCase();
    final idx = currentList.indexWhere((r) =>
        r.id == incoming.id ||
        (cleanBNo.isNotEmpty && r.billNo.trim().toUpperCase() == cleanBNo));

    if (incoming.isDeleted == 1) {
      if (idx != -1) {
        final local = currentList[idx];
        if (incoming.updatedAt >= local.updatedAt || incoming.version > local.version) {
          currentList.removeAt(idx);
          debugPrint("🗑️ [DebitNoteSyncModule] Evicted deleted debit note: ${incoming.billNo}");
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
