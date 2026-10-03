
/// SyncIdentityGuard: Ensures IDs are never mutated or discarded during Edit/Modify,
/// and attaches precise UTC timestamps to prevent zombie bill resurrects.
class SyncIdentityGuard {
  /// Ensures existing ID is locked and preserved during edit/modification.
  /// If [existingId] is present and valid, it returns the exact existingId.
  /// Otherwise, it generates a clean, uniform system ID.
  static String resolveId({
    required String? existingId,
    required String prefix,
    String? referenceNo,
  }) {
    if (existingId != null &&
        existingId.trim().isNotEmpty &&
        existingId.trim() != 'temp' &&
        existingId.trim() != 'DRAFT') {
      return existingId.trim();
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    final String cleanPrefix = prefix.trim().toUpperCase();
    if (referenceNo != null &&
        referenceNo.trim().isNotEmpty &&
        referenceNo.trim() != 'DRAFT') {
      final cleanRef = referenceNo.replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '').toUpperCase();
      return '$cleanPrefix-$cleanRef-$now';
    }
    return '$cleanPrefix-$now';
  }

  /// Current UTC timestamp in ISO-8601 for collision-free conflict resolution
  static String nowUtcString() {
    return DateTime.now().toUtc().toIso8601String();
  }

  /// Generates a quick checksum hash of the map to verify if content actually changed
  static String generateHash(Map<String, dynamic> data) {
    final sortedKeys = data.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in sortedKeys) {
      if (key == 'updatedAt' || key == 'syncedAt') continue;
      buffer.write('$key:${data[key]};');
    }
    return buffer.toString().hashCode.toRadixString(16);
  }
}
