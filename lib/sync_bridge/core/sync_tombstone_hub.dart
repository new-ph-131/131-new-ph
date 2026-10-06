import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// SyncTombstoneHub: Centralized Deletion Engine for both App and Web layers.
/// Guarantees that any deleted record (bill, inward, voucher, return, challan)
/// is permanently recorded so it can NEVER be resurrected by cloud merge engines.
class SyncTombstoneHub {
  static const String tombstoneFileName = 'tombstones.json';

  /// Loads all tombstone IDs from the local filesystem working directory.
  static Future<Set<String>> loadFromDisk(String workingDir) async {
    if (workingDir.isEmpty) return <String>{};
    try {
      final file = File('$workingDir/$tombstoneFileName');
      if (await file.exists()) {
        final content = await file.readAsString();
        final dynamic decoded = jsonDecode(content);
        if (decoded is List) {
          return decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toSet();
        }
      }
    } catch (_) {}
    return <String>{};
  }

  /// Saves the unified tombstone set atomically to the working directory.
  static Future<void> saveToDisk(String workingDir, Set<String> tombstones) async {
    if (workingDir.isEmpty) return;
    try {
      final file = File('$workingDir/$tombstoneFileName');
      await file.writeAsString(jsonEncode(tombstones.toList()));
    } catch (_) {}
  }

  /// Permanently records a deletion in both memory, disk file, and SharedPreferences.
  static Future<void> markDeleted({
    required String workingDir,
    required String companyId,
    required String id,
    String? referenceNo,
  }) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    // 1. Update SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'tombstones_$companyId';
      final localList = (prefs.getStringList(key) ?? <String>[]).toSet();
      localList.add(cleanId);
      if (referenceNo != null && referenceNo.trim().isNotEmpty) {
        localList.add(referenceNo.trim());
      }
      await prefs.setStringList(key, localList.toList());

      final uKey = 'unmarked_tombstones_$companyId';
      final uList = (prefs.getStringList(uKey) ?? <String>[]).toSet();
      if (cleanId.isNotEmpty) uList.remove(cleanId);
      if (referenceNo != null && referenceNo.trim().isNotEmpty) {
        uList.remove(referenceNo.trim());
      }
      await prefs.setStringList(uKey, uList.toList());
    } catch (_) {}

    // 2. Update tombstones.json in working directory
    if (workingDir.isNotEmpty) {
      final diskSet = await loadFromDisk(workingDir);
      diskSet.add(cleanId);
      if (referenceNo != null && referenceNo.trim().isNotEmpty) {
        diskSet.add(referenceNo.trim());
      }
      await saveToDisk(workingDir, diskSet);
    }
  }

  /// Unmarks a tombstone when a record is newly imported or recreated with higher version
  static Future<void> unmarkDeleted({
    required String workingDir,
    required String companyId,
    required String id,
    String? referenceNo,
  }) async {
    final cleanId = id.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'tombstones_$companyId';
      final localList = (prefs.getStringList(key) ?? <String>[]).toSet();
      if (cleanId.isNotEmpty) localList.remove(cleanId);
      if (referenceNo != null && referenceNo.trim().isNotEmpty) {
        localList.remove(referenceNo.trim());
      }
      await prefs.setStringList(key, localList.toList());

      final uKey = 'unmarked_tombstones_$companyId';
      final uList = (prefs.getStringList(uKey) ?? <String>[]).toSet();
      if (cleanId.isNotEmpty) uList.add(cleanId);
      if (referenceNo != null && referenceNo.trim().isNotEmpty) {
        uList.add(referenceNo.trim());
      }
      await prefs.setStringList(uKey, uList.toList());
    } catch (_) {}
    if (workingDir.isNotEmpty) {
      final diskSet = await loadFromDisk(workingDir);
      if (cleanId.isNotEmpty) diskSet.remove(cleanId);
      if (referenceNo != null && referenceNo.trim().isNotEmpty) {
        diskSet.remove(referenceNo.trim());
      }
      await saveToDisk(workingDir, diskSet);
    }
  }

  /// Checks if a record ID or reference number has been marked as deleted.
  static bool isDeleted(Set<String> tombstones, String id, {String? referenceNo}) {
    if (tombstones.contains(id.trim())) return true;
    if (referenceNo != null && referenceNo.trim().isNotEmpty && tombstones.contains(referenceNo.trim())) {
      return true;
    }
    return false;
  }
}
