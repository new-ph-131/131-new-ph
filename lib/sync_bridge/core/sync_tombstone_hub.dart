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

  /// Permanently records a deletion in memory, disk file, and SharedPreferences. (#PH-REV-806)
  static Future<void> markDeleted({
    String workingDir = "",
    String companyId = "",
    required String id,
    String? referenceNo,
    String? fy,
  }) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    final rawRef = referenceNo?.trim() ?? "";
    final isBareInt = rawRef.isNotEmpty && RegExp(r"^\d{1,9}$").hasMatch(rawRef);
    final scopedRef = (fy != null && fy.trim().isNotEmpty && rawRef.isNotEmpty) ? "$fy::$rawRef" : "";

    // 1. Update SharedPreferences cache
    if (companyId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'tombstones_$companyId';
        final localList = (prefs.getStringList(key) ?? <String>[]).toSet();
        localList.add(cleanId);
        if (scopedRef.isNotEmpty) {
          localList.add(scopedRef);
        }
        if (rawRef.isNotEmpty && !isBareInt) {
          localList.add(rawRef);
        }
        await prefs.setStringList(key, localList.toList());

        final uKey = 'unmarked_tombstones_$companyId';
        final uList = (prefs.getStringList(uKey) ?? <String>[]).toSet();
        uList.remove(cleanId);
        uList.remove(cleanId.toUpperCase());
        if (scopedRef.isNotEmpty) {
          uList.remove(scopedRef);
          uList.remove(scopedRef.toUpperCase());
        }
        if (rawRef.isNotEmpty) {
          uList.remove(rawRef);
          uList.remove(rawRef.toUpperCase());
        }
        await prefs.setStringList(uKey, uList.toList());
      } catch (_) {}
    }

    // 2. Update tombstones.json in working directory
    if (workingDir.isNotEmpty) {
      final diskSet = await loadFromDisk(workingDir);
      diskSet.add(cleanId);
      if (scopedRef.isNotEmpty) {
        diskSet.add(scopedRef);
      }
      if (rawRef.isNotEmpty && !isBareInt) {
        diskSet.add(rawRef);
      }
      await saveToDisk(workingDir, diskSet);
    }
  }

  /// Unmarks a tombstone when a record is newly imported or recreated with higher version (#PH-REV-806)
  static Future<void> unmarkDeleted({
    String workingDir = "",
    String companyId = "",
    required String id,
    String? referenceNo,
    String? fy,
  }) async {
    final cleanId = id.trim();
    final rawRef = referenceNo?.trim() ?? "";
    final scopedRef = (fy != null && fy.trim().isNotEmpty && rawRef.isNotEmpty) ? "$fy::$rawRef" : "";

    if (companyId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'tombstones_$companyId';
        final localList = (prefs.getStringList(key) ?? <String>[]).toSet();
        if (cleanId.isNotEmpty) {
          localList.remove(cleanId);
          localList.remove(cleanId.toUpperCase());
        }
        if (scopedRef.isNotEmpty) {
          localList.remove(scopedRef);
          localList.remove(scopedRef.toUpperCase());
        }
        if (rawRef.isNotEmpty) {
          localList.remove(rawRef);
          localList.remove(rawRef.toUpperCase());
        }
        await prefs.setStringList(key, localList.toList());

        final uKey = 'unmarked_tombstones_$companyId';
        final uList = (prefs.getStringList(uKey) ?? <String>[]).toSet();
        if (cleanId.isNotEmpty) {
          uList.add(cleanId);
          uList.add(cleanId.toUpperCase());
        }
        if (scopedRef.isNotEmpty) {
          uList.add(scopedRef);
          uList.add(scopedRef.toUpperCase());
        }
        if (rawRef.isNotEmpty) {
          uList.add(rawRef);
          uList.add(rawRef.toUpperCase());
        }
        await prefs.setStringList(uKey, uList.toList());
      } catch (_) {}
    }

    if (workingDir.isNotEmpty) {
      final diskSet = await loadFromDisk(workingDir);
      if (cleanId.isNotEmpty) {
        diskSet.remove(cleanId);
        diskSet.remove(cleanId.toUpperCase());
      }
      if (scopedRef.isNotEmpty) {
        diskSet.remove(scopedRef);
        diskSet.remove(scopedRef.toUpperCase());
      }
      if (rawRef.isNotEmpty) {
        diskSet.remove(rawRef);
        diskSet.remove(rawRef.toUpperCase());
      }
      await saveToDisk(workingDir, diskSet);
    }
  }

  /// Checks if a record ID or reference number has been marked as deleted (#PH-REV-806).
  static bool isDeleted(Set<String> tombstones, String id, {String? referenceNo, String? fy}) {
    final cleanId = id.trim();
    if (cleanId.isNotEmpty && (tombstones.contains(cleanId) || tombstones.contains(cleanId.toUpperCase()))) {
      return true;
    }
    if (referenceNo != null && referenceNo.trim().isNotEmpty) {
      final cleanRef = referenceNo.trim();
      if (fy != null && fy.trim().isNotEmpty) {
        final scopedRef = "$fy::$cleanRef";
        if (tombstones.contains(scopedRef) || tombstones.contains(scopedRef.toUpperCase())) {
          return true;
        }
      }
      final isBareInt = RegExp(r"^\d{1,9}$").hasMatch(cleanRef);
      if (!(isBareInt && fy != null && fy.trim().isNotEmpty)) {
        if (tombstones.contains(cleanRef) || tombstones.contains(cleanRef.toUpperCase())) {
          return true;
        }
      }
    }
    return false;
  }
}
