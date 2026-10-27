// FILE: lib/sync_core/modules/gst_diary_sync_module.dart
// Revision: #PH-REV-785 (GST-DIARY-DEDICATED-D1-SYNC-MODULE)

import '../../gst/gst_diary/gst_diary_models.dart';
import '../models/sync_envelope.dart';
import '../outbox/sync_queue_manager.dart';

/// GstDiarySyncModule: Dedicated D1 Outbox + Cloud Snapshot LWW Sync Engine for GST Diary Sessions (#PH-REV-785)
/// Strict File Separation Rule: Isolated from Sales, Purchases, Vouchers, and Challans.
class GstDiarySyncModule {
  static const String docType = "GST_DIARY_SESSION";

  /// 📤 1. ENQUEUE OUTBOX MUTATION FOR D1 BATCH SYNC
  static void onSessionSaved(
    GstDiarySession session,
    String storeToken, {
    bool isDelete = false,
  }) {
    if (storeToken.trim().isEmpty) return;

    final Map<String, dynamic> payload = session.toMap();
    payload["doc_type"] = docType;
    if (isDelete) {
      payload["isDeleted"] = 1;
      payload["is_deleted"] = 1;
      payload["status"] = "Deleted";
    }

    SyncQueueManager.enqueueMutation(
      syncId: session.id.trim(),
      storeToken: storeToken.trim().toUpperCase(),
      docType: docType,
      currentVersion: session.version,
      isDelete: isDelete,
      rawPayload: payload,
    );
  }

  /// 📥 2. MERGE INCOMING ENVELOPE FROM D1 BATCH
  static bool mergeIncomingSessionEnvelope(
    List<GstDiarySession> localSessions,
    SyncEnvelope envelope,
  ) {
    final Map<String, dynamic> map = envelope.billData;
    String id = envelope.syncId.trim();
    if (id.isEmpty) {
      id = (map["id"] ?? "").toString().trim();
    }
    if (id.isEmpty) return false;

    final int incomingVersion = envelope.version > 0
        ? envelope.version
        : (int.tryParse(map["version"]?.toString() ?? "1") ?? 1);
    final int incomingTimestamp = envelope.updatedAt > 0
        ? envelope.updatedAt
        : (int.tryParse(map["updatedAt"]?.toString() ?? map["updated_at"]?.toString() ?? "0") ??
            DateTime.now().millisecondsSinceEpoch);
    final bool isDel = envelope.isDeleted == 1 ||
        envelope.action == "DELETE" ||
        (int.tryParse(map["isDeleted"]?.toString() ?? map["is_deleted"]?.toString() ?? "0") == 1) ||
        map["status"] == "Deleted";

    final int existingIdx = localSessions.indexWhere(
      (s) => s.id.trim().toUpperCase() == id.toUpperCase(),
    );

    if (isDel) {
      if (existingIdx != -1) {
        localSessions.removeAt(existingIdx);
        return true;
      }
      return false;
    }

    final incomingSession = GstDiarySession.fromMap(map);
    incomingSession.id = id;
    incomingSession.version = incomingVersion;
    incomingSession.updatedAt = incomingTimestamp;
    incomingSession.isDeleted = 0;

    if (existingIdx != -1) {
      final local = localSessions[existingIdx];
      if (incomingVersion >= local.version ||
          incomingTimestamp >= local.updatedAt ||
          local.updatedAt == 0) {
        localSessions[existingIdx] = incomingSession;
        localSessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return true;
      }
      return false;
    } else {
      localSessions.insert(0, incomingSession);
      localSessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return true;
    }
  }

  /// 🔄 3. MERGE CLOUD gst_sessions.json SNAPSHOT WITH LWW & TOMBSTONE SHIELD
  static bool mergeSessionList({
    required List<dynamic>? cloudSessionList,
    required List<GstDiarySession> localSessionList,
    required Map<String, int> tombstoneRegistry,
    Set<String>? deletedIds,
  }) {
    bool hasChanged = false;

    bool isTombstoned(String key, int recordTs) {
      final k = key.trim();
      if (k.isEmpty) return false;
      final u = k.toUpperCase();
      if (deletedIds != null && (deletedIds.contains(k) || deletedIds.contains(u))) {
        final delTs = tombstoneRegistry[k] ?? tombstoneRegistry[u] ?? 0;
        if (delTs == 0 || recordTs == 0 || delTs >= recordTs) return true;
      }
      if (tombstoneRegistry.containsKey(k) || tombstoneRegistry.containsKey(u)) {
        final delTs = tombstoneRegistry[k] ?? tombstoneRegistry[u] ?? 0;
        if (delTs == 0 || recordTs == 0 || delTs >= recordTs) return true;
      }
      return false;
    }

    // Purge locally tombstoned sessions
    final beforeLen = localSessionList.length;
    localSessionList.removeWhere((s) => s.isDeleted == 1 || isTombstoned(s.id, s.updatedAt));
    if (localSessionList.length != beforeLen) hasChanged = true;

    if (cloudSessionList == null) return hasChanged;

    for (final raw in cloudSessionList) {
      if (raw is! Map) continue;
      final cloudMap = Map<String, dynamic>.from(raw);
      final String id = (cloudMap["id"] ?? "").toString().trim();
      if (id.isEmpty) continue;

      final int cloudVer = int.tryParse(cloudMap["version"]?.toString() ?? "1") ?? 1;
      final int cloudTs = int.tryParse(
            cloudMap["updatedAt"]?.toString() ??
                cloudMap["updated_at"]?.toString() ??
                cloudMap["createdAt"]?.toString() ??
                "0",
          ) ??
          0;
      final int isDeleted = int.tryParse(
            cloudMap["isDeleted"]?.toString() ??
                cloudMap["is_deleted"]?.toString() ??
                (cloudMap["status"] == "Deleted" ? "1" : "0"),
          ) ??
          0;

      if (isDeleted == 1 || isTombstoned(id, cloudTs)) {
        final localIdx = localSessionList.indexWhere(
          (s) => s.id.trim().toUpperCase() == id.toUpperCase(),
        );
        if (localIdx != -1) {
          localSessionList.removeAt(localIdx);
          hasChanged = true;
        }
        if (isDeleted == 1) {
          tombstoneRegistry[id] = cloudTs > 0 ? cloudTs : DateTime.now().millisecondsSinceEpoch;
        }
        continue;
      }

      final existingIdx = localSessionList.indexWhere(
        (s) => s.id.trim().toUpperCase() == id.toUpperCase(),
      );
      if (existingIdx != -1) {
        final local = localSessionList[existingIdx];
        final bool fieldDiff = local.status != (cloudMap["status"] ?? local.status) ||
            local.title != (cloudMap["title"] ?? local.title) ||
            local.remarks != (cloudMap["remarks"] ?? local.remarks) ||
            local.deductedAmount != ((cloudMap["deductedAmount"] ?? local.deductedAmount) as num).toDouble();

        if (cloudVer > local.version ||
            (cloudVer == local.version && cloudTs > local.updatedAt) ||
            (local.updatedAt == 0 && fieldDiff)) {
          final merged = GstDiarySession.fromMap(cloudMap);
          localSessionList[existingIdx] = merged;
          hasChanged = true;
        }
      } else {
        localSessionList.add(GstDiarySession.fromMap(cloudMap));
        hasChanged = true;
      }
    }

    if (hasChanged) {
      localSessionList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return hasChanged;
  }
}
