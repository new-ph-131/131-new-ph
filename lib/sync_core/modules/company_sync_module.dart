// FILE: lib/sync_core/modules/company_sync_module.dart
import "../../models.dart";
import "../../logic/master_cascade_service.dart";
import "../models/sync_envelope.dart";
import "../outbox/sync_queue_manager.dart";

/// CompanySyncModule: Dedicated D1 + Cloud Snapshot Sync & Cascade Engine for Company / Brand Master (#PH-REV-768)
class CompanySyncModule {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  /// 📤 1. D1 OUTBOX ENQUEUE: Push Company Mutation directly to Cloudflare D1
  static void onCompanySaved(
    Company comp,
    String storeToken, {
    bool isDelete = false,
    String? previousName,
  }) {
    if (storeToken.trim().isEmpty || comp.id.trim().isEmpty) return;
    final payload = Map<String, dynamic>.from(comp.toMap());
    if (previousName != null && previousName.trim().isNotEmpty) {
      payload["previousName"] = previousName.trim().toUpperCase();
    }
    SyncQueueManager.enqueueMutation(
      syncId: comp.id.trim(),
      storeToken: storeToken.trim().toUpperCase(),
      docType: "COMPANY",
      currentVersion: comp.version,
      isDelete: isDelete,
      rawPayload: payload,
    );
  }

  /// 📥 2. MERGE INCOMING ENVELOPE FROM D1 BATCH
  static bool mergeIncomingCompanyEnvelope(
    List<Company> localCompanyList,
    SyncEnvelope envelope, {
    List<Medicine>? medicines,
    List<ShortageItem>? shortages,
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

    int existingIdx = localCompanyList.indexWhere((c) {
      if (id.isNotEmpty && c.id.trim().toUpperCase() == id.toUpperCase()) return true;
      if (cleanPrevKey.isNotEmpty && cleanString(c.name) == cleanPrevKey) return true;
      return cleanNameKey.isNotEmpty && cleanString(c.name) == cleanNameKey;
    });

    if (isDel) {
      if (existingIdx != -1) {
        localCompanyList.removeAt(existingIdx);
        return true;
      }
      return false;
    }

    if (existingIdx != -1) {
      final localComp = localCompanyList[existingIdx];
      final oldLocalName = localComp.name;
      if (incomingVersion >= localComp.version ||
          incomingTimestamp >= localComp.updatedAt ||
          localComp.updatedAt == 0 ||
          localComp.name.trim().toUpperCase() != name) {
        final merged = Company.fromMap(map);
        if (localComp.id.isNotEmpty) {
          merged.id = localComp.id;
        }
        merged.name = name;
        merged.version = incomingVersion;
        merged.updatedAt = incomingTimestamp;
        localCompanyList[existingIdx] = merged;

        if (medicines != null) {
          MasterCascadeService.cascadeCompanyUpdate(
            updatedCompany: merged,
            previousName: prevName.isNotEmpty ? prevName : oldLocalName,
            medicines: medicines,
            shortages: shortages,
          );
        }
        return true;
      }
      return false;
    } else {
      final newComp = Company.fromMap(map);
      if (newComp.id.isEmpty) newComp.id = id;
      newComp.name = name;
      newComp.version = incomingVersion;
      newComp.updatedAt = incomingTimestamp;
      localCompanyList.add(newComp);
      if (medicines != null) {
        MasterCascadeService.cascadeCompanyUpdate(
          updatedCompany: newComp,
          previousName: prevName.isNotEmpty ? prevName : null,
          medicines: medicines,
          shortages: shortages,
        );
      }
      return true;
    }
  }

  /// 🔄 3. MERGE CLOUD comps.json SNAPSHOT WITH LWW, TOMBSTONE SHIELD & CASCADE RENAME
  static bool mergeCompanyList({
    required List<dynamic>? cloudCompanyList,
    required List<Company> localCompanyList,
    required Map<String, int> tombstoneRegistry,
    Set<String>? deletedIds,
    List<Medicine>? medicines,
    List<ShortageItem>? shortages,
  }) {
    if (cloudCompanyList == null) return false;
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

    // Purge any locally tombstoned company
    final beforeLen = localCompanyList.length;
    localCompanyList.removeWhere((c) => isTombstoned(c.id, c.updatedAt) || isTombstoned("COMP_${cleanString(c.name)}", c.updatedAt));
    if (localCompanyList.length != beforeLen) hasChanged = true;

    for (var raw in cloudCompanyList) {
      if (raw is! Map) continue;
      final cloudMap = Map<String, dynamic>.from(raw);
      final String id = (cloudMap["id"] ?? "").toString().trim();
      final String name = (cloudMap["name"] ?? "").toString().trim().toUpperCase();
      final String cleanNameKey = cleanString(name);
      final int cloudVer = int.tryParse(cloudMap["version"]?.toString() ?? "1") ?? 1;
      final int cloudTs = int.tryParse(cloudMap["updatedAt"]?.toString() ?? cloudMap["updated_at"]?.toString() ?? "0") ?? 0;
      final int isDeleted = int.tryParse(cloudMap["isDeleted"]?.toString() ?? cloudMap["is_deleted"]?.toString() ?? "0") ?? 0;

      if (id.isEmpty && cleanNameKey.isEmpty) continue;

      if (isDeleted == 1 || isTombstoned(id, cloudTs) || isTombstoned("COMP_$cleanNameKey", cloudTs)) {
        int localIdx = localCompanyList.indexWhere((c) =>
            (id.isNotEmpty && c.id.trim().toUpperCase() == id.toUpperCase()) ||
            (cleanNameKey.isNotEmpty && cleanString(c.name) == cleanNameKey));
        if (localIdx != -1) {
          localCompanyList.removeAt(localIdx);
          hasChanged = true;
        }
        if (isDeleted == 1 && id.isNotEmpty) {
          tombstoneRegistry[id] = cloudTs > 0 ? cloudTs : DateTime.now().millisecondsSinceEpoch;
        }
        continue;
      }

      // Match by ID first so renames (e.g. CIPLA -> PIPLA) match the existing Company!
      int existingIdx = -1;
      if (id.isNotEmpty) {
        existingIdx = localCompanyList.indexWhere((c) => c.id.trim().toUpperCase() == id.toUpperCase());
      }
      if (existingIdx == -1 && cleanNameKey.isNotEmpty) {
        existingIdx = localCompanyList.indexWhere((c) => cleanString(c.name) == cleanNameKey);
      }

      if (existingIdx != -1) {
        final localComp = localCompanyList[existingIdx];
        final String oldName = localComp.name;
        final bool nameDiff = localComp.name.trim().toUpperCase() != name;
        if (cloudVer > localComp.version ||
            (cloudVer == localComp.version && cloudTs > localComp.updatedAt) ||
            (localComp.updatedAt == 0 && nameDiff)) {
          final merged = Company.fromMap(cloudMap);
          if (localComp.id.isNotEmpty) merged.id = localComp.id;
          merged.name = name;
          localCompanyList[existingIdx] = merged;
          hasChanged = true;

          if (nameDiff && medicines != null) {
            MasterCascadeService.cascadeCompanyUpdate(
              updatedCompany: merged,
              previousName: oldName,
              medicines: medicines,
              shortages: shortages,
            );
          }
        }
      } else {
        final newComp = Company.fromMap(cloudMap);
        newComp.name = name;
        localCompanyList.add(newComp);
        hasChanged = true;
      }
    }

    // Deduplicate by cleaned name while keeping highest version/updatedAt
    final Map<String, Company> dedupById = {};
    final Map<String, String> nameToId = {};
    for (final c in localCompanyList) {
      final cid = c.id.trim();
      final cnameKey = cleanString(c.name);
      if (cid.isEmpty || cnameKey.isEmpty) continue;
      if (nameToId.containsKey(cnameKey)) {
        final existingId = nameToId[cnameKey]!;
        final existing = dedupById[existingId]!;
        if (c.version > existing.version || (c.version == existing.version && c.updatedAt > existing.updatedAt)) {
          dedupById[existingId] = Company(
            id: existing.id,
            name: c.name.trim().toUpperCase(),
            version: c.version,
            updatedAt: c.updatedAt,
          );
        }
      } else {
        dedupById[cid] = c;
        nameToId[cnameKey] = cid;
      }
    }
    if (dedupById.length != localCompanyList.length) {
      localCompanyList
        ..clear()
        ..addAll(dedupById.values);
      hasChanged = true;
    }

    return hasChanged;
  }
}
