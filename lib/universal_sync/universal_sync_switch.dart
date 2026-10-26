// FILE: lib/universal_sync/universal_sync_switch.dart
// Live Revision: #PH-REV-782 (GST-DIARY-RESPONSIVE-VIEWPORT-STABILITY)

/// UniversalSyncSwitch: Safe Master Feature Toggle.
/// Allows instant switching between the new Universal Track and Legacy Sync without deleting files.
class UniversalSyncSwitch {
  static const String revision = "#PH-REV-782 (GST-DIARY-RESPONSIVE-VIEWPORT-STABILITY)";

  /// Master switch: Set to false to revert back to legacy sale sync instantly
  static bool isUniversalSyncActive = true;

  /// High-concurrency 1-second burst compactor active flag
  static bool isCompactorActive = true;
}

// Trigger build run: 1792001075.6415167
