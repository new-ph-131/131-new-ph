// FILE: lib/sync_core/outbox/sync_queue_manager.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/sync_envelope.dart';

/// SyncQueueManager: Transactional Outbox Engine for Pharoah ERP.
/// Collects rapid local mutations, eliminates burst clicks, and flushes
/// debounced JSON batches to the Cloudflare Edge D1 Bus.
class SyncQueueManager {
  static final SyncQueueManager instance = SyncQueueManager._internal();
  SyncQueueManager._internal();

  static final List<SyncEnvelope> _outboxBufferQueue = [];
  static Timer? _debounceTimer;
  static bool _isFlushing = false;
  static const String edgeSignalEndpoint = "https://pharoah-erp.pages.dev/api/lab_signal";

  /// Enqueues a local mutation to the outbox buffer.
  /// Deduplicates operations within the local frame buffer (replaces older pending ops for same syncId).
  static void enqueueMutation({
    required String syncId,
    required String storeToken,
    required String docType,
    required int currentVersion,
    required bool isDelete,
    required Map<String, dynamic> rawPayload,
    Duration debounceDuration = const Duration(milliseconds: 400),
  }) {
    if (syncId.trim().isEmpty) return;

    final envelope = SyncEnvelope(
      syncId: syncId.trim(),
      storeToken: storeToken.trim().toUpperCase(),
      documentType: docType.trim().toUpperCase(),
      version: currentVersion + 1,
      updatedAt: DateTime.now().microsecondsSinceEpoch, // 16-Digit Microsecond Clock
      isDeleted: isDelete ? 1 : 0,
      billData: rawPayload,
    );

    // Frame buffer deduplication: remove any pending op for the same syncId
    _outboxBufferQueue.removeWhere((element) => element.syncId == envelope.syncId);
    _outboxBufferQueue.add(envelope);

    debugPrint("📥 [SyncQueueManager] Enqueued mutation: doc=${envelope.documentType}, id=${envelope.syncId}, ver=${envelope.version}, delete=${envelope.isDeleted}");

    // 400ms Debounce Clock
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      flushOutboxAsJSONBatch();
    });
  }

  /// Flushes all pending outbox envelopes as an aggregated atomic JSON batch
  static Future<bool> flushOutboxAsJSONBatch() async {
    if (_outboxBufferQueue.isEmpty || _isFlushing) return false;
    _isFlushing = true;

    // Snapshot current outbox buffer
    final List<SyncEnvelope> batchPayload = List.from(_outboxBufferQueue);
    _outboxBufferQueue.clear();

    final String token = batchPayload.first.storeToken;

    final Map<String, dynamic> body = {
      "storeToken": token,
      "source": "OUTBOX_BATCH",
      "action": "JSON_BATCH_MUTATION",
      "batch_timestamp": DateTime.now().millisecondsSinceEpoch,
      "operations": batchPayload.map((e) => e.toMap()).toList(),
    };

    try {
      final response = await http.post(
        Uri.parse(edgeSignalEndpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        debugPrint("⚡ [SyncQueueManager] Successfully flushed batch of ${batchPayload.length} operations to D1!");
        _isFlushing = false;
        return true;
      } else {
        debugPrint("⚠ [SyncQueueManager] Server returned status ${response.statusCode}. Restoring to buffer.");
        _outboxBufferQueue.insertAll(0, batchPayload);
        _isFlushing = false;
        return false;
      }
    } catch (e) {
      debugPrint("⚠ [SyncQueueManager] Batch flush error: $e. Restoring to buffer for retry.");
      _outboxBufferQueue.insertAll(0, batchPayload);
      _isFlushing = false;
      return false;
    }
  }

  /// Pending count for UI status inspection
  static int get pendingCount => _outboxBufferQueue.length;
}
