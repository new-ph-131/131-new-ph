// FILE: lib/universal_sync/engine/universal_reactive_store.dart
// Live Revision: #PH-REV-695 (UNIVERSAL-MULTI-TAB-EDGE-CONCURRENCY-PRO)
import "package:flutter/foundation.dart";
import "../models/universal_transaction.dart";
import "../coordinator/tab_session_coordinator.dart";

/// UniversalReactiveStore: Zero-Flicker in-place list reconciler.
/// Guarantees:
/// 1. Self-Echo Suppression (Ignores mutations originating from this exact tab)
/// 2. In-place index updates (Never clears list or re-inserts at 0 for updates)
/// 3. Strict Monotonic Versioning (LWW using integer version, not wall-clock)
/// 4. Permanent Tombstone Enforcement (Deleted records can never resurrect)
class UniversalReactiveStore {
  static final Set<String> _tombstones = {};

  static Set<String> get tombstones => _tombstones;

  /// In-place mutation for any strongly-typed list
  static bool applyTransactionToList<T>({
    required List<T> list,
    required UniversalTransaction tx,
    required String Function(T) getId,
    required int Function(T) getVersion,
    required T Function(Map<String, dynamic>) fromMap,
  }) {
    // 1. Self-Echo Suppression
    if (TabSessionCoordinator.isSelfOrigin(tx.clientSource)) {
      return false; // Skip local echoes
    }

    final targetGuid = tx.guid.trim();
    if (targetGuid.isEmpty) return false;

    // 2. Case: Deletion / Tombstone
    if (tx.isDeleted == 1) {
      _tombstones.add(targetGuid);
      final idx = list.indexWhere((e) => getId(e).trim().toUpperCase() == targetGuid.toUpperCase());
      if (idx != -1) {
        list.removeAt(idx);
        debugPrint("🗑️ [UniversalReactiveStore] Evicted deleted ${tx.docType}: $targetGuid");
        return true;
      }
      return false;
    }

    // 3. Tombstone check (Anti-Zombie)
    if (_tombstones.contains(targetGuid)) {
      debugPrint("🛑 [UniversalReactiveStore] Dropped zombie resurrection for: $targetGuid");
      return false;
    }

    // 4. Case: Active Record Update or Insert
    final idx = list.indexWhere((e) => getId(e).trim().toUpperCase() == targetGuid.toUpperCase());

    if (idx != -1) {
      // In-place Update: Compare integer versions
      final currentVer = getVersion(list[idx]);
      if (tx.version > currentVer) {
        // In-place replacement at exact index -> Zero scroll jump, zero flicker!
        list[idx] = fromMap(tx.payload);
        debugPrint("🔄 [UniversalReactiveStore] In-place patched ${tx.docType} $targetGuid (v$currentVer -> v${tx.version})");
        return true;
      }
      return false; // Stale packet, ignore
    } else {
      // New Record -> Clean insert at index 0
      list.insert(0, fromMap(tx.payload));
      debugPrint("✨ [UniversalReactiveStore] Inserted new ${tx.docType}: $targetGuid (v${tx.version})");
      return true;
    }
  }
}
