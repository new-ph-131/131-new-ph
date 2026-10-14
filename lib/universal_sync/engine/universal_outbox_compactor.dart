// FILE: lib/universal_sync/engine/universal_outbox_compactor.dart
// Live Revision: #PH-REV-695 (UNIVERSAL-MULTI-TAB-EDGE-CONCURRENCY-PRO)
import "dart:async";
import "dart:convert";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "../models/universal_transaction.dart";
import "../coordinator/tab_session_coordinator.dart";

/// UniversalOutboxCompactor: High-concurrency rapid-fire buffer.
/// Implements Operation Squashing for 1-second burst clicks:
///  - INSERT + UPDATE = Coalesced INSERT (latest payload)
///  - INSERT + DELETE = NO-OP (cancelled locally before network hit)
///  - UPDATE + UPDATE = Compacted UPDATE (version incremented)
///  - UPDATE + DELETE = Final DELETE (tombstoned)
class UniversalOutboxCompactor {
  static final UniversalOutboxCompactor instance = UniversalOutboxCompactor._internal();
  UniversalOutboxCompactor._internal();

  static final Map<String, UniversalTransaction> _buffer = {};
  static Timer? _debounceTimer;
  static bool _isFlushing = false;
  static const String edgeEndpoint = "https://pharoah-erp.pages.dev/api/lab_signal";

  /// Enqueues a transaction into the compaction buffer
  static void enqueueMutation({
    required String guid,
    required String docType,
    required int version,
    required bool isDelete,
    required Map<String, dynamic> payload,
    required String storeToken,
    Duration debounceTime = const Duration(milliseconds: 350),
  }) {
    final cleanGuid = guid.trim();
    if (cleanGuid.isEmpty || storeToken.trim().isEmpty) return;

    final existing = _buffer[cleanGuid];
    final now = DateTime.now().millisecondsSinceEpoch;

    if (existing != null) {
      // 1. Rapid click squashing
      if (existing.isDeleted == 0 && isDelete) {
        if (existing.version <= 1) {
          // Created and deleted in same buffer window -> NO-OP! Cancel out completely!
          _buffer.remove(cleanGuid);
          debugPrint("⚡ [OutboxCompactor] Squashed & Cancelled NO-OP for: $cleanGuid");
          return;
        } else {
          // Existing record updated then deleted -> Keep final DELETE
          _buffer[cleanGuid] = UniversalTransaction(
            guid: cleanGuid,
            docType: docType,
            version: existing.version + 1,
            seq: 0,
            updatedAt: now,
            isDeleted: 1,
            clientSource: TabSessionCoordinator.sessionId,
            payload: payload,
          );
        }
      } else {
        // Multiple updates -> coalesce into latest payload with incremented version
        _buffer[cleanGuid] = UniversalTransaction(
          guid: cleanGuid,
          docType: docType,
          version: existing.version + 1,
          seq: 0,
          updatedAt: now,
          isDeleted: isDelete ? 1 : 0,
          clientSource: TabSessionCoordinator.sessionId,
          payload: payload,
        );
      }
    } else {
      // Brand new entry in buffer
      _buffer[cleanGuid] = UniversalTransaction(
        guid: cleanGuid,
        docType: docType,
        version: version,
        seq: 0,
        updatedAt: now,
        isDeleted: isDelete ? 1 : 0,
        clientSource: TabSessionCoordinator.sessionId,
        payload: payload,
      );
    }

    // Debounce network dispatch
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceTime, () => _flushBuffer(storeToken));
  }

  static Future<void> _flushBuffer(String storeToken) async {
    if (_isFlushing || _buffer.isEmpty) return;
    _isFlushing = true;

    final batchToFlush = Map<String, UniversalTransaction>.from(_buffer);
    _buffer.clear();

    try {
      final payloadList = batchToFlush.values.map((tx) => tx.toMap()).toList();
      final body = jsonEncode({
        "storeToken": storeToken.trim().toUpperCase(),
        "clientSource": TabSessionCoordinator.sessionId,
        "batch": payloadList,
      });

      final res = await http.post(
        Uri.parse(edgeEndpoint),
        headers: {"Content-Type": "application/json"},
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        debugPrint("✔ [OutboxCompactor] Successfully flushed ${batchToFlush.length} compacted mutations to Cloudflare Edge");
      } else {
        debugPrint("⚠ [OutboxCompactor] Edge flush status: ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("⚠ [OutboxCompactor] Network error flushing batch: $e");
      // Put back into buffer if failed
      for (final entry in batchToFlush.entries) {
        if (!_buffer.containsKey(entry.key)) {
          _buffer[entry.key] = entry.value;
        }
      }
    } finally {
      _isFlushing = false;
    }
  }
}
