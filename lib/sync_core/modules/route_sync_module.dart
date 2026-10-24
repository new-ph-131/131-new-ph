// FILE: lib/sync_core/modules/route_sync_module.dart
import "../../models.dart";
import "../../logic/master_cascade_service.dart";
import "../models/sync_envelope.dart";
import "../outbox/sync_queue_manager.dart";

/// RouteSyncModule: Dedicated D1 + Cloud Snapshot Sync & Cascade Engine for Route / Area Master (#PH-REV-768)
class RouteSyncModule {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  /// 📤 1. D1 OUTBOX ENQUEUE: Push Route Mutation directly to Cloudflare D1
  static void onRouteSaved(
    RouteArea route,
    String storeToken, {
    bool isDelete = false,
    String? previousName,
  }) {
    if (storeToken.trim().isEmpty || route.id.trim().isEmpty) return;
    final payload = Map<String, dynamic>.from(route.toMap());
    if (previousName != null && previousName.trim().isNotEmpty) {
      payload["previousName"] = previousName.trim().toUpperCase();
    }
    SyncQueueManager.enqueueMutation(
      syncId: route.id.trim(),
      storeToken: storeToken.trim().toUpperCase(),
      docType: "ROUTE",
      currentVersion: route.version,
      isDelete: isDelete,
      rawPayload: payload,
    );
  }

  /// 📥 2. MERGE INCOMING ENVELOPE FROM D1 BATCH
  static bool mergeIncomingRouteEnvelope(
    List<RouteArea> localRouteList,
    SyncEnvelope envelope, {
    List<Party>? parties,
  }) {
    final Map<String, dynamic> map = envelope.billData;
    String id = envelope.syncId.trim();
    if (id.isEmpty) {
      id = (map["id"] ?? "").toString().trim();
    }
    String name = (map["name"] ?? "").toString().trim().toUpperCase();
    String prevName = (map["previousName"] ?? "").toString().trim().toUpperCase();
    String cleanNameKey = cleanString(name);
    String cleanPrevKey = cleanString(prevName);

    int incomingVersion = envelope.version > 0 ? envelope.version : (int.tryParse(map["version"]?.toString() ?? "1") ?? 1);
    int incomingTimestamp = envelope.updatedAt > 0
        ? envelope.updatedAt
        : (int.tryParse(map["updatedAt"]?.toString() ?? "0") ?? DateTime.now().millisecondsSinceEpoch);
    bool isDel = envelope.isDeleted == 1 || envelope.action == "DELETE" || (int.tryParse(map["isDeleted"]?.toString() ?? "0") == 1);

    if (id.isEmpty && cleanNameKey.isEmpty) return false;

    int existingIdx = localRouteList.indexWhere((r) {
      if (id.isNotEmpty && r.id.trim().toUpperCase() == id.toUpperCase()) return true;
      if (cleanPrevKey.isNotEmpty && cleanString(r.name) == cleanPrevKey) return true;
      return cleanNameKey.isNotEmpty && cleanString(r.name) == cleanNameKey;
    });

    if (isDel) {
      if (existingIdx != -1) {
        localRouteList.removeAt(existingIdx);
        return true;
      }
      return false;
    }

    if (existingIdx != -1) {
      final localRoute = localRouteList[existingIdx];
      final oldLocalName = localRoute.name;
      if (incomingVersion >= localRoute.version ||
          incomingTimestamp >= localRoute.updatedAt ||
          localRoute.updatedAt == 0 ||
          localRoute.name.trim().toUpperCase() != name) {
        final merged = RouteArea.fromMap(map);
        if (localRoute.id.isNotEmpty) {
          merged.id = localRoute.id;
        }
        merged.name = name;
        merged.version = incomingVersion;
        merged.updatedAt = incomingTimestamp;
        localRouteList[existingIdx] = merged;

        if (parties != null) {
          MasterCascadeService.cascadeRouteUpdate(
            updatedRoute: merged,
            previousName: prevName.isNotEmpty ? prevName : oldLocalName,
            parties: parties,
          );
        }
        return true;
      }
      return false;
    } else {
      final newRoute = RouteArea.fromMap(map);
      if (newRoute.id.isEmpty) newRoute.id = id;
      newRoute.name = name;
      newRoute.version = incomingVersion;
      newRoute.updatedAt = incomingTimestamp;
      localRouteList.add(newRoute);
      if (parties != null) {
        MasterCascadeService.cascadeRouteUpdate(
          updatedRoute: newRoute,
          previousName: prevName.isNotEmpty ? prevName : null,
          parties: parties,
        );
      }
      return true;
    }
  }

  /// 🔄 3. MERGE CLOUD routs.json SNAPSHOT WITH LWW, TOMBSTONE SHIELD & CASCADE RENAME
  static bool mergeRouteList({
    required List<dynamic>? cloudRouteList,
    required List<RouteArea> localRouteList,
    required Map<String, int> tombstoneRegistry,
    Set<String>? deletedIds,
    List<Party>? parties,
  }) {
    if (cloudRouteList == null) return false;
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

    final beforeLen = localRouteList.length;
    localRouteList.removeWhere((r) => isTombstoned(r.id, r.updatedAt) || isTombstoned("ROUTE_${cleanString(r.name)}", r.updatedAt));
    if (localRouteList.length != beforeLen) hasChanged = true;

    for (var raw in cloudRouteList) {
      if (raw is! Map) continue;
      final cloudMap = Map<String, dynamic>.from(raw);
      final String id = (cloudMap["id"] ?? "").toString().trim();
      final String name = (cloudMap["name"] ?? "").toString().trim().toUpperCase();
      final String cleanNameKey = cleanString(name);
      final int cloudVer = int.tryParse(cloudMap["version"]?.toString() ?? "1") ?? 1;
      final int cloudTs = int.tryParse(cloudMap["updatedAt"]?.toString() ?? cloudMap["updated_at"]?.toString() ?? "0") ?? 0;
      final int isDeleted = int.tryParse(cloudMap["isDeleted"]?.toString() ?? cloudMap["is_deleted"]?.toString() ?? "0") ?? 0;

      if (id.isEmpty && cleanNameKey.isEmpty) continue;

      if (isDeleted == 1 || isTombstoned(id, cloudTs) || isTombstoned("ROUTE_$cleanNameKey", cloudTs)) {
        int localIdx = localRouteList.indexWhere((r) =>
            (id.isNotEmpty && r.id.trim().toUpperCase() == id.toUpperCase()) ||
            (cleanNameKey.isNotEmpty && cleanString(r.name) == cleanNameKey));
        if (localIdx != -1) {
          localRouteList.removeAt(localIdx);
          hasChanged = true;
        }
        if (isDeleted == 1 && id.isNotEmpty) {
          tombstoneRegistry[id] = cloudTs > 0 ? cloudTs : DateTime.now().millisecondsSinceEpoch;
        }
        continue;
      }

      int existingIdx = -1;
      if (id.isNotEmpty) {
        existingIdx = localRouteList.indexWhere((r) => r.id.trim().toUpperCase() == id.toUpperCase());
      }
      if (existingIdx == -1 && cleanNameKey.isNotEmpty) {
        existingIdx = localRouteList.indexWhere((r) => cleanString(r.name) == cleanNameKey);
      }

      if (existingIdx != -1) {
        final localRoute = localRouteList[existingIdx];
        final String oldName = localRoute.name;
        final bool nameDiff = localRoute.name.trim().toUpperCase() != name;
        if (cloudVer > localRoute.version ||
            (cloudVer == localRoute.version && cloudTs > localRoute.updatedAt) ||
            (localRoute.updatedAt == 0 && nameDiff)) {
          final merged = RouteArea.fromMap(cloudMap);
          if (localRoute.id.isNotEmpty) merged.id = localRoute.id;
          merged.name = name;
          localRouteList[existingIdx] = merged;
          hasChanged = true;

          if (nameDiff && parties != null) {
            MasterCascadeService.cascadeRouteUpdate(
              updatedRoute: merged,
              previousName: oldName,
              parties: parties,
            );
          }
        }
      } else {
        final newRoute = RouteArea.fromMap(cloudMap);
        newRoute.name = name;
        localRouteList.add(newRoute);
        hasChanged = true;
      }
    }

    final Map<String, RouteArea> dedupById = {};
    final Map<String, String> nameToId = {};
    for (final r in localRouteList) {
      final rid = r.id.trim();
      final rnameKey = cleanString(r.name);
      if (rid.isEmpty || rnameKey.isEmpty) continue;
      if (nameToId.containsKey(rnameKey)) {
        final existingId = nameToId[rnameKey]!;
        final existing = dedupById[existingId]!;
        if (r.version > existing.version || (r.version == existing.version && r.updatedAt > existing.updatedAt)) {
          dedupById[existingId] = RouteArea(
            id: existing.id,
            name: r.name.trim().toUpperCase(),
            version: r.version,
            updatedAt: r.updatedAt,
          );
        }
      } else {
        dedupById[rid] = r;
        nameToId[rnameKey] = rid;
      }
    }
    if (dedupById.length != localRouteList.length) {
      localRouteList
        ..clear()
        ..addAll(dedupById.values);
      hasChanged = true;
    }

    return hasChanged;
  }
}
