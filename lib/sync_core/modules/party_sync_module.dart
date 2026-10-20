// FILE: lib/sync_core/modules/party_sync_module.dart
import "dart:convert";
import "../../models.dart";
import "../../pharoah_manager.dart";
import "../models/sync_envelope.dart";
import "../outbox/sync_queue_manager.dart";

/// 🛡️ PARTY MASTER SYNC MODULE (#PH-REV-734)
/// Handles 360-degree all-field mirroring, LWW monotonic versioning,
/// 4-tier deduplication (ID -> GST -> Phone -> CleanName), D1 Outbox integration,
/// and Tombstone deletion shielding across App & Web.
class PartySyncModule {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  static String cleanPhone(String phone) {
    String digits = phone.replaceAll(RegExp(r"[^0-9]"), "");
    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }
    return digits;
  }

  static String cleanGst(String gst) {
    String g = gst.trim().toUpperCase();
    if (g == "N/A" || g == "NA" || g == "NONE" || g == "0" || g.length < 5) return "";
    return g;
  }

  /// 📤 1. D1 OUTBOX ENQUEUE: Push Party Mutation directly to Cloudflare D1
  static void onPartySaved(Party party, String storeToken, {bool isDelete = false}) {
    if (storeToken.trim().isEmpty || party.id.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: party.id.trim(),
      storeToken: storeToken.trim().toUpperCase(),
      docType: 'PARTY',
      currentVersion: party.version,
      isDelete: isDelete,
      rawPayload: party.toMap(),
    );
  }

  /// 📥 2. MERGE INCOMING ENVELOPE FROM D1 BATCH
  static bool mergeIncomingPartyEnvelope(List<Party> localPartyList, SyncEnvelope envelope) {
    final Map<String, dynamic> partyMap = envelope.billData;
    String id = envelope.syncId.trim();
    if (id.isEmpty) {
      id = (partyMap["id"] ?? "").toString().trim();
    }
    String name = (partyMap["name"] ?? "").toString().trim();
    String phone = cleanPhone((partyMap["phone"] ?? "").toString());
    String gst = cleanGst((partyMap["gst"] ?? "").toString());
    String cleanNameKey = cleanString(name);
    int incomingVersion = envelope.version > 0 ? envelope.version : 1;
    int incomingTimestamp = envelope.updatedAt > 0 ? envelope.updatedAt : DateTime.now().millisecondsSinceEpoch;
    bool isDel = envelope.isDeleted == 1 || envelope.action == "DELETE";

    if (id.isEmpty && cleanNameKey.isEmpty) return false;

    // 4-Tier Deduplication Match
    int existingIdx = localPartyList.indexWhere((p) {
      if (id.isNotEmpty && p.id.trim() == id) return true;
      String pGst = cleanGst(p.gst);
      if (gst.isNotEmpty && pGst.isNotEmpty && pGst == gst) return true;
      String pPhone = cleanPhone(p.phone);
      if (phone.isNotEmpty && pPhone.isNotEmpty && pPhone == phone) return true;
      return cleanNameKey.isNotEmpty && cleanString(p.name) == cleanNameKey;
    });

    if (isDel) {
      if (existingIdx != -1) {
        localPartyList.removeAt(existingIdx);
        return true;
      }
      return false;
    }

    if (existingIdx != -1) {
      final localParty = localPartyList[existingIdx];
      // LWW Check: Overwrite if incoming version is higher, or same version with newer timestamp
      if (incomingVersion > localParty.version ||
          (incomingVersion == localParty.version && incomingTimestamp >= localParty.updatedAt) ||
          localParty.updatedAt == 0) {
        final mergedParty = Party.fromMap(partyMap);
        // Ensure ID is preserved if matched via name/phone
        if (localParty.id.isNotEmpty && mergedParty.id != localParty.id) {
          mergedParty.id = localParty.id;
        }
        mergedParty.version = incomingVersion;
        mergedParty.updatedAt = incomingTimestamp;
        localPartyList[existingIdx] = mergedParty;
        return true;
      }
      return false;
    } else {
      final newParty = Party.fromMap(partyMap);
      if (newParty.id.isEmpty) newParty.id = id;
      newParty.version = incomingVersion;
      newParty.updatedAt = incomingTimestamp;
      localPartyList.add(newParty);
      return true;
    }
  }

  /// Registers or Updates Party Activity with full deduplication & 18-box field synchronization
  static void registerPartyActivity({
    required PharoahManager ph,
    required Party updatedParty,
  }) {
    String cleanNewName = cleanString(updatedParty.name);
    String cleanPPhone = cleanPhone(updatedParty.phone);
    String cleanPGst = cleanGst(updatedParty.gst);

    int existingIdx = ph.parties.indexWhere((p) {
      if (updatedParty.id.isNotEmpty && p.id == updatedParty.id) return true;
      String existingGst = cleanGst(p.gst);
      if (cleanPGst.isNotEmpty && existingGst.isNotEmpty && existingGst == cleanPGst) return true;
      String existingPhone = cleanPhone(p.phone);
      if (cleanPPhone.isNotEmpty && existingPhone.isNotEmpty && existingPhone == cleanPPhone) return true;
      return cleanString(p.name) == cleanNewName && cleanNewName.isNotEmpty;
    });

    final nowTs = DateTime.now().millisecondsSinceEpoch;
    if (existingIdx != -1) {
      final localParty = ph.parties[existingIdx];
      // Preserve original ID & update in-place with incremented version
      updatedParty.id = localParty.id;
      updatedParty.version = localParty.version + 1;
      updatedParty.updatedAt = nowTs;
      ph.parties[existingIdx] = updatedParty;
    } else {
      if (updatedParty.id.isEmpty || updatedParty.id.contains(" ") || updatedParty.id == "0" || updatedParty.id == "temp") {
        updatedParty.id = "PARTY-$nowTs";
      }
      updatedParty.version = updatedParty.version > 0 ? updatedParty.version : 1;
      updatedParty.updatedAt = nowTs;
      ph.parties.add(updatedParty);
    }
    ph.save();
    ph.notifyListeners();
  }

  /// Merges incoming cloud/web Party list with local device list
  static bool mergePartyList({
    required List<dynamic>? cloudPartyList,
    required List<Party> localPartyList,
    required Map<String, int> tombstoneRegistry,
  }) {
    if (cloudPartyList == null) return false;
    bool hasChanged = false;

    for (var rawMap in cloudPartyList) {
      if (rawMap is! Map<String, dynamic>) continue;
      final cloudMap = rawMap;
      String id = (cloudMap["id"] ?? "").toString().trim();
      String name = (cloudMap["name"] ?? "").toString().trim();
      String phone = cleanPhone((cloudMap["phone"] ?? "").toString());
      String gst = cleanGst((cloudMap["gst"] ?? "").toString());
      String cleanNameKey = cleanString(name);

      int cloudVersion = int.tryParse(cloudMap["version"]?.toString() ?? "1") ?? 1;
      int cloudTimestamp = int.tryParse(cloudMap["updatedAt"]?.toString() ?? cloudMap["updated_at"]?.toString() ?? "0") ?? 0;
      int isDeleted = int.tryParse(cloudMap["isDeleted"]?.toString() ?? cloudMap["is_deleted"]?.toString() ?? "0") ?? 0;

      if (id.isEmpty && cleanNameKey.isEmpty) continue;

      // 🛡️ Tombstone Check
      if (tombstoneRegistry.containsKey(id) || (phone.isNotEmpty && tombstoneRegistry.containsKey(phone))) {
        int delTs = tombstoneRegistry[id] ?? (phone.isNotEmpty ? tombstoneRegistry[phone] : null) ?? 0;
        if (delTs == 0 || cloudTimestamp <= delTs) {
          int localIdx = localPartyList.indexWhere((p) => p.id == id || (cleanNameKey.isNotEmpty && cleanString(p.name) == cleanNameKey));
          if (localIdx != -1) {
            localPartyList.removeAt(localIdx);
            hasChanged = true;
          }
          continue;
        }
      }

      int existingIdx = localPartyList.indexWhere((p) {
        if (id.isNotEmpty && p.id == id) return true;
        String pGst = cleanGst(p.gst);
        if (gst.isNotEmpty && pGst.isNotEmpty && pGst == gst) return true;
        String pPhone = cleanPhone(p.phone);
        if (phone.isNotEmpty && pPhone.isNotEmpty && pPhone == phone) return true;
        return cleanString(p.name) == cleanNameKey && cleanNameKey.isNotEmpty;
      });

      if (isDeleted == 1) {
        if (existingIdx != -1) {
          localPartyList.removeAt(existingIdx);
          hasChanged = true;
        }
        if (id.isNotEmpty) tombstoneRegistry[id] = cloudTimestamp > 0 ? cloudTimestamp : DateTime.now().millisecondsSinceEpoch;
        continue;
      }

      if (existingIdx != -1) {
        var localParty = localPartyList[existingIdx];
        if (cloudVersion > localParty.version ||
            (cloudVersion == localParty.version && cloudTimestamp >= localParty.updatedAt) ||
            localParty.updatedAt == 0) {
          final merged = Party.fromMap(cloudMap);
          if (localParty.id.isNotEmpty && merged.id != localParty.id) {
            merged.id = localParty.id; // Preserve established ID
          }
          localPartyList[existingIdx] = merged;
          hasChanged = true;
        }
      } else {
        localPartyList.add(Party.fromMap(cloudMap));
        hasChanged = true;
      }
    }
    return hasChanged;
  }
}
