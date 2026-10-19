// FILE: lib/sync_core/modules/party_sync_module.dart
import "dart:convert";
import "../../models.dart";
import "../../pharoah_manager.dart";

/// 🛡️ PARTY MASTER SYNC MODULE
/// Handles 360-degree all-field mirroring, LWW monotonic versioning,
/// and Tombstone deletion shielding for Party / Ledger Master across App & Web.
class PartySyncModule {
  /// Resolves Party System ID or ID
  static String getCompositeKey(Party party) {
    return party.id.trim();
  }

  /// Registers or Updates Party Activity with full 18-box field synchronization
  static void registerPartyActivity({
    required PharoahManager ph,
    required Party updatedParty,
  }) {
    int existingIdx = ph.parties.indexWhere((p) =>
      p.id == updatedParty.id ||
      (updatedParty.phone.isNotEmpty && p.phone.trim() == updatedParty.phone.trim()) ||
      (updatedParty.gst.isNotEmpty && p.gst.trim().toUpperCase() == updatedParty.gst.trim().toUpperCase())
    );

    if (existingIdx != -1) {
      final localParty = ph.parties[existingIdx];
      // Increment version if updating locally
      if (updatedParty.version <= localParty.version) {
        updatedParty.version = localParty.version + 1;
      }
      updatedParty.updatedAt = DateTime.now().millisecondsSinceEpoch;
      ph.parties[existingIdx] = updatedParty;
    } else {
      updatedParty.version = updatedParty.version > 0 ? updatedParty.version : 1;
      updatedParty.updatedAt = DateTime.now().millisecondsSinceEpoch;
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
      int cloudVersion = int.tryParse(cloudMap["version"]?.toString() ?? "1") ?? 1;
      int cloudTimestamp = int.tryParse(cloudMap["updatedAt"]?.toString() ?? cloudMap["updated_at"]?.toString() ?? "0") ?? 0;
      int isDeleted = int.tryParse(cloudMap["isDeleted"]?.toString() ?? cloudMap["is_deleted"]?.toString() ?? "0") ?? 0;

      if (id.isEmpty) continue;

      // 🛡️ Tombstone Check
      if (tombstoneRegistry.containsKey(id) || (phone.isNotEmpty && tombstoneRegistry.containsKey(phone))) {
        int delTs = tombstoneRegistry[id] ?? tombstoneRegistry[phone] ?? 0;
        if (delTs == 0 || cloudTimestamp <= delTs) {
          int localIdx = localPartyList.indexWhere((p) => p.id == id);
          if (localIdx != -1) {
            localPartyList.removeAt(localIdx);
            hasChanged = true;
          }
          continue;
        }
      }

      int existingIdx = localPartyList.indexWhere((p) =>
        p.id == id ||
        (gst.isNotEmpty && p.gst.trim().toUpperCase() == gst)
      );

      if (isDeleted == 1) {
        if (existingIdx != -1) {
          localPartyList.removeAt(existingIdx);
          hasChanged = true;
        }
        tombstoneRegistry[id] = cloudTimestamp > 0 ? cloudTimestamp : DateTime.now().millisecondsSinceEpoch;
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
