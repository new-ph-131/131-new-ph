// FILE: lib/sync_core/modules/party_sync_module.dart
import "dart:convert";
import "../../models.dart";
import "../../pharoah_manager.dart";

/// 🛡️ PARTY MASTER SYNC MODULE
/// Handles 360-degree all-field mirroring, LWW monotonic versioning,
/// name/phone/gst deduplication, and Tombstone deletion shielding across App & Web.
class PartySyncModule {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  /// Registers or Updates Party Activity with full deduplication & 18-box field synchronization
  static void registerPartyActivity({
    required PharoahManager ph,
    required Party updatedParty,
  }) {
    String cleanNewName = cleanString(updatedParty.name);
    String cleanPhone = updatedParty.phone.trim();
    String cleanGst = updatedParty.gst.trim().toUpperCase();

    int existingIdx = ph.parties.indexWhere((p) {
      if (updatedParty.id.isNotEmpty && p.id == updatedParty.id) return true;
      if (cleanGst.isNotEmpty && cleanGst != "N/A" && p.gst.trim().toUpperCase() == cleanGst) return true;
      if (cleanPhone.isNotEmpty && p.phone.trim() == cleanPhone) return true;
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
      if (updatedParty.id.isEmpty || updatedParty.id.contains(" ")) {
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
      String phone = (cloudMap["phone"] ?? "").toString().trim();
      String gst = (cloudMap["gst"] ?? "").toString().trim().toUpperCase();
      String cleanNameKey = cleanString(name);

      int cloudVersion = int.tryParse(cloudMap["version"]?.toString() ?? "1") ?? 1;
      int cloudTimestamp = int.tryParse(cloudMap["updatedAt"]?.toString() ?? cloudMap["updated_at"]?.toString() ?? "0") ?? 0;
      int isDeleted = int.tryParse(cloudMap["isDeleted"]?.toString() ?? cloudMap["is_deleted"]?.toString() ?? "0") ?? 0;

      if (id.isEmpty && cleanNameKey.isEmpty) continue;

      // 🛡️ Tombstone Check
      if (tombstoneRegistry.containsKey(id) || (phone.isNotEmpty && tombstoneRegistry.containsKey(phone))) {
        int delTs = tombstoneRegistry[id] ?? tombstoneRegistry[phone] ?? 0;
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
        if (gst.isNotEmpty && gst != "N/A" && p.gst.trim().toUpperCase() == gst) return true;
        if (phone.isNotEmpty && p.phone.trim() == phone) return true;
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
          localPartyList[existingIdx] = Party.fromMap(cloudMap);
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
