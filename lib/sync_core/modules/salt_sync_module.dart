// FILE: lib/sync_core/modules/salt_sync_module.dart
import "../../models.dart";
import "../../logic/master_cascade_service.dart";
import "../models/sync_envelope.dart";
import "../outbox/sync_queue_manager.dart";

/// SaltSyncModule: Dedicated D1 + Cloud Snapshot Sync & Cascade Engine for Salt / Composition Master (#PH-REV-768)
class SaltSyncModule {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  /// 📤 1. D1 OUTBOX ENQUEUE: Push Salt Mutation directly to Cloudflare D1
  static void onSaltSaved(
    Salt salt,
    String storeToken, {
    bool isDelete = false,
    String? previousName,
  }) {
    if (storeToken.trim().isEmpty || salt.id.trim().isEmpty) return;
    final payload = Map<String, dynamic>.from(salt.toMap());
    if (previousName != null && previousName.trim().isNotEmpty) {
      payload["previousName"] = previousName.trim().toUpperCase();
    }
    SyncQueueManager.enqueueMutation(
      syncId: salt.id.trim(),
      storeToken: storeToken.trim().toUpperCase(),
      docType: "SALT",
      currentVersion: salt.version,
      isDelete: isDelete,
      rawPayload: payload,
    );
  }

  /// 📥 2. MERGE INCOMING ENVELOPE FROM D1 BATCH
  static bool mergeIncomingSaltEnvelope(
    List<Salt> localSaltList,
    SyncEnvelope envelope, {
    List<Medicine>? medicines,
  }) {
    final Map<String, dynamic> map = envelope.billData;
    String id = envelope.syncId.trim();
    if (id.isEmpty) {
      id = (map["id"] ?? "").toString().trim();
    }
    String name = (map["name"] ?? "").toString().trim().toUpperCase();
    String type = (map["type"] ?? "Mono").toString().trim();
    if (type.isEmpty) type = "Mono";
    String prevName = (map["previousName"] ?? "").toString().trim().toUpperCase();
    String cleanNameKey = cleanString(name);
    String cleanPrevKey = cleanString(prevName);

    int incomingVersion = envelope.version > 0 ? envelope.version : (int.tryParse(map["version"]?.toString() ?? "1") ?? 1);
    int incomingTimestamp = envelope.updatedAt > 0
        ? envelope.updatedAt
        : (int.tryParse(map["updatedAt"]?.toString() ?? "0") ?? DateTime.now().millisecondsSinceEpoch);
    bool isDel = envelope.isDeleted == 1 || envelope.action == "DELETE" || (int.tryParse(map["isDeleted"]?.toString() ?? "0") == 1);

    if (id.isEmpty && cleanNameKey.isEmpty) return false;

    int existingIdx = localSaltList.indexWhere((s) {
      if (id.isNotEmpty && s.id.trim().toUpperCase() == id.toUpperCase()) return true;
      if (cleanPrevKey.isNotEmpty && cleanString(s.name) == cleanPrevKey) return true;
      return cleanNameKey.isNotEmpty && cleanString(s.name) == cleanNameKey;
    });

    if (isDel) {
      if (existingIdx != -1) {
        localSaltList.removeAt(existingIdx);
        return true;
      }
      return false;
    }

    if (existingIdx != -1) {
      final localSalt = localSaltList[existingIdx];
      final oldLocalName = localSalt.name;
      if (incomingVersion >= localSalt.version ||
          incomingTimestamp >= localSalt.updatedAt ||
          localSalt.updatedAt == 0 ||
          localSalt.name.trim().toUpperCase() != name ||
          localSalt.type != type) {
        final merged = Salt.fromMap(map);
        if (localSalt.id.isNotEmpty) {
          merged.id = localSalt.id;
        }
        merged.name = name;
        merged.type = type;
        merged.version = incomingVersion;
        merged.updatedAt = incomingTimestamp;
        localSaltList[existingIdx] = merged;

        if (medicines != null) {
          MasterCascadeService.cascadeSaltUpdate(
            updatedSalt: merged,
            previousName: prevName.isNotEmpty ? prevName : oldLocalName,
            medicines: medicines,
          );
        }
        return true;
      }
      return false;
    } else {
      final newSalt = Salt.fromMap(map);
      if (newSalt.id.isEmpty) newSalt.id = id;
      newSalt.name = name;
      newSalt.type = type;
      newSalt.version = incomingVersion;
      newSalt.updatedAt = incomingTimestamp;
      localSaltList.add(newSalt);
      if (medicines != null) {
        MasterCascadeService.cascadeSaltUpdate(
          updatedSalt: newSalt,
          previousName: prevName.isNotEmpty ? prevName : null,
          medicines: medicines,
        );
      }
      return true;
    }
  }

  /// 🔄 3. MERGE CLOUD salts.json SNAPSHOT WITH LWW, TOMBSTONE SHIELD & CASCADE RENAME
  static bool mergeSaltList({
    required List<dynamic>? cloudSaltList,
    required List<Salt> localSaltList,
    required Map<String, int> tombstoneRegistry,
    Set<String>? deletedIds,
    List<Medicine>? medicines,
  }) {
    if (cloudSaltList == null) return false;
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

    final beforeLen = localSaltList.length;
    localSaltList.removeWhere((s) => isTombstoned(s.id, s.updatedAt) || isTombstoned("SALT_${cleanString(s.name)}", s.updatedAt));
    if (localSaltList.length != beforeLen) hasChanged = true;

    for (var raw in cloudSaltList) {
      if (raw is! Map) continue;
      final cloudMap = Map<String, dynamic>.from(raw);
      final String id = (cloudMap["id"] ?? "").toString().trim();
      final String name = (cloudMap["name"] ?? "").toString().trim().toUpperCase();
      final String type = (cloudMap["type"] ?? "Mono").toString().trim();
      final String cleanNameKey = cleanString(name);
      final int cloudVer = int.tryParse(cloudMap["version"]?.toString() ?? "1") ?? 1;
      final int cloudTs = int.tryParse(cloudMap["updatedAt"]?.toString() ?? cloudMap["updated_at"]?.toString() ?? "0") ?? 0;
      final int isDeleted = int.tryParse(cloudMap["isDeleted"]?.toString() ?? cloudMap["is_deleted"]?.toString() ?? "0") ?? 0;

      if (id.isEmpty && cleanNameKey.isEmpty) continue;

      if (isDeleted == 1 || isTombstoned(id, cloudTs) || isTombstoned("SALT_$cleanNameKey", cloudTs)) {
        int localIdx = localSaltList.indexWhere((s) =>
            (id.isNotEmpty && s.id.trim().toUpperCase() == id.toUpperCase()) ||
            (cleanNameKey.isNotEmpty && cleanString(s.name) == cleanNameKey));
        if (localIdx != -1) {
          localSaltList.removeAt(localIdx);
          hasChanged = true;
        }
        if (isDeleted == 1 && id.isNotEmpty) {
          tombstoneRegistry[id] = cloudTs > 0 ? cloudTs : DateTime.now().millisecondsSinceEpoch;
        }
        continue;
      }

      int existingIdx = -1;
      if (id.isNotEmpty) {
        existingIdx = localSaltList.indexWhere((s) => s.id.trim().toUpperCase() == id.toUpperCase());
      }
      if (existingIdx == -1 && cleanNameKey.isNotEmpty) {
        existingIdx = localSaltList.indexWhere((s) => cleanString(s.name) == cleanNameKey);
      }

      if (existingIdx != -1) {
        final localSalt = localSaltList[existingIdx];
        final String oldName = localSalt.name;
        final bool fieldDiff = localSalt.name.trim().toUpperCase() != name || localSalt.type != type;
        if (cloudVer > localSalt.version ||
            (cloudVer == localSalt.version && cloudTs > localSalt.updatedAt) ||
            (localSalt.updatedAt == 0 && fieldDiff)) {
          final merged = Salt.fromMap(cloudMap);
          if (localSalt.id.isNotEmpty) merged.id = localSalt.id;
          merged.name = name;
          merged.type = type.isNotEmpty ? type : "Mono";
          localSaltList[existingIdx] = merged;
          hasChanged = true;

          if (fieldDiff && medicines != null) {
            MasterCascadeService.cascadeSaltUpdate(
              updatedSalt: merged,
              previousName: oldName,
              medicines: medicines,
            );
          }
        }
      } else {
        final newSalt = Salt.fromMap(cloudMap);
        newSalt.name = name;
        localSaltList.add(newSalt);
        hasChanged = true;
      }
    }

    final Map<String, Salt> dedupById = {};
    final Map<String, String> nameToId = {};
    for (final s in localSaltList) {
      final sid = s.id.trim();
      final snameKey = cleanString(s.name);
      if (sid.isEmpty || snameKey.isEmpty) continue;
      if (nameToId.containsKey(snameKey)) {
        final existingId = nameToId[snameKey]!;
        final existing = dedupById[existingId]!;
        if (s.version > existing.version || (s.version == existing.version && s.updatedAt > existing.updatedAt)) {
          dedupById[existingId] = Salt(
            id: existing.id,
            name: s.name.trim().toUpperCase(),
            type: s.type,
            version: s.version,
            updatedAt: s.updatedAt,
          );
        }
      } else {
        dedupById[sid] = s;
        nameToId[snameKey] = sid;
      }
    }
    if (dedupById.length != localSaltList.length) {
      localSaltList
        ..clear()
        ..addAll(dedupById.values);
      hasChanged = true;
    }

    return hasChanged;
  }
}
