// FILE: lib/realtime_signaling/transport/cloud_signal_channel.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/sync_signal_event.dart';

/// CloudSignalChannel: Low-latency event signaling bus between App & Web.
/// Routes through Cloudflare Edge (<30ms) to bypass Google Drive latency.
class CloudSignalChannel {
  static final CloudSignalChannel instance = CloudSignalChannel._internal();
  CloudSignalChannel._internal();

  static const String edgeSignalEndpoint = "https://pharoah-erp.pages.dev/api/lab_signal";
  Timer? _pollTimer;
  int _lastKnownSignalTime = 0;
  int _lastKnownBatchTime = 0;
  bool _isChecking = false;

  /// Broadcasts a fast mutation signal to Cloudflare Edge Relay
  Future<bool> broadcastSignal(SyncSignalEvent event) async {
    try {
      if (event.storeToken.isEmpty) return false;

      final payload = {
        "storeToken": event.storeToken,
        "source": event.source.toUpperCase(),
        "action": event.action,
        "entityId": event.entityId,
        "timestamp": event.timestamp,
        "deletedIds": event.deletedIds,
        "unmarkedIds": event.unmarkedIds,
        "financialYear": event.financialYear,
        "fy": event.financialYear,
        "delta": event.delta,
      };

      final response = await http.post(
        Uri.parse(edgeSignalEndpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 4));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint("⚠ [CloudSignalChannel] Broadcast error: $e");
      return false;
    }
  }

  /// Pure chronological aggregator for incoming signal event maps (testable offline).
  static ({
    SyncSignalEvent? mergedEvent,
    int maxTimestamp,
  }) aggregateRemoteSignals({
    required List<Map<String, dynamic>> rawEvents,
    required String mySource,
    required int lastSeenTs,
  }) {
    final cleanSource = mySource.trim().toUpperCase();
    final Map<String, Map<String, dynamic>> dedupedById = {};
    final List<Map<String, dynamic>> noIdList = [];
    for (final raw in rawEvents) {
      final evId = (raw['id'] ?? '').toString().trim();
      if (evId.isNotEmpty) {
        dedupedById[evId] = raw;
      } else {
        noIdList.add(raw);
      }
    }
    final ordered = [...dedupedById.values, ...noIdList];
    ordered.sort((a, b) {
      int ta = int.tryParse((a['timestamp'] ?? '0').toString()) ?? 0;
      int tb = int.tryParse((b['timestamp'] ?? '0').toString()) ?? 0;
      if (ta > 100000000000000) ta ~/= 1000;
      if (tb > 100000000000000) tb ~/= 1000;
      final cmp = ta.compareTo(tb);
      if (cmp != 0) return cmp;
      // Same millisecond: process non-delete before delete so rapid modify+delete stays deleted
      final aDel = (a['action'] ?? '').toString().toUpperCase().contains('DELETE') ? 1 : 0;
      final bDel = (b['action'] ?? '').toString().toUpperCase().contains('DELETE') ? 1 : 0;
      return aDel.compareTo(bDel);
    });

    SyncSignalEvent? latestRemoteEvent;
    final Set<String> aggregatedDeletedIds = {};
    final Set<String> aggregatedUnmarkedIds = {};
    int maxSigTs = lastSeenTs;

    for (final rawEv in ordered) {
      final ev = SyncSignalEvent.fromMap(rawEv);
      int evTs = ev.timestamp;
      if (evTs > 100000000000000) evTs ~/= 1000;
      if (evTs > lastSeenTs) {
        if (evTs > maxSigTs) maxSigTs = evTs;
        final src = ev.source.trim().toUpperCase();
        if (src != cleanSource) {
          for (final u in ev.unmarkedIds) {
            final cu = u.trim();
            if (cu.isEmpty) continue;
            aggregatedUnmarkedIds.add(cu);
            aggregatedDeletedIds.remove(cu);
            if (!cu.contains('_')) aggregatedDeletedIds.remove(cu.toUpperCase());
          }
          for (final d in ev.deletedIds) {
            final cd = d.trim();
            if (cd.isEmpty) continue;
            aggregatedDeletedIds.add(cd);
            aggregatedUnmarkedIds.remove(cd);
            if (!cd.contains('_')) aggregatedUnmarkedIds.remove(cd.toUpperCase());
          }
          latestRemoteEvent = ev;
        }
      }
    }

    if (latestRemoteEvent == null) {
      return (mergedEvent: null, maxTimestamp: maxSigTs);
    }
    return (
      mergedEvent: SyncSignalEvent(
        storeToken: latestRemoteEvent.storeToken,
        source: latestRemoteEvent.source,
        action: latestRemoteEvent.action,
        entityId: latestRemoteEvent.entityId,
        timestamp: latestRemoteEvent.timestamp,
        companyId: latestRemoteEvent.companyId,
        deletedIds: aggregatedDeletedIds.toList(),
        unmarkedIds: aggregatedUnmarkedIds.toList(),
        financialYear: latestRemoteEvent.financialYear,
        delta: latestRemoteEvent.delta,
      ),
      maxTimestamp: maxSigTs,
    );
  }

  /// Starts listening for incoming events from the opposite client
  void listenToSignals({
    required String storeToken,
    required String mySource, // 'app' or 'web'
    required Function(SyncSignalEvent) onSignal,
    dynamic Function(List<dynamic>)? onBatchReceived,
    Function(List<String>)? onTombstonesReceived,
    Duration interval = const Duration(milliseconds: 3000),
  }) {
    stopListening();
    if (storeToken.isEmpty) return;

    // Subtract 30s lookback window to prevent device clock skew between Mobile App & Web PC from skipping fresh events
    final int nowMs = DateTime.now().millisecondsSinceEpoch - 30000;
    _lastKnownSignalTime = nowMs;
    _lastKnownBatchTime = nowMs;
    final cleanToken = storeToken.trim().toUpperCase();
    final cleanSource = mySource.trim().toUpperCase();

    _pollTimer = Timer.periodic(interval, (_) async {
      if (_isChecking) return;
      _isChecking = true;

      try {
        final int queryTs = _lastKnownSignalTime < _lastKnownBatchTime
            ? _lastKnownSignalTime
            : _lastKnownBatchTime;
        final int normalizedTs = queryTs > 100000000000000 ? queryTs ~/ 1000 : queryTs;

        final uri = Uri.parse(
          "$edgeSignalEndpoint?storeToken=${Uri.encodeComponent(cleanToken)}"
          "&lastSeenTs=$normalizedTs"
        );

        final response = await http.get(uri).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'SUCCESS') {
            // 🛡️ Edge Gravestones Ingestion
            if (data['tombstones'] is List && (data['tombstones'] as List).isNotEmpty) {
              final edgeTombs = List<String>.from(
                (data['tombstones'] as List)
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty),
              );
              if (edgeTombs.isNotEmpty) {
                onTombstonesReceived?.call(edgeTombs);
              }
            }

            // 🚀 Step 4: Atomic Batch Delta Processing (uses separate _lastKnownBatchTime cursor)
            if (data['batch_operations'] is List && (data['batch_operations'] as List).isNotEmpty) {
              final rawOps = List<dynamic>.from(data['batch_operations']);
              final freshOps = <dynamic>[];
              int maxBatchTs = _lastKnownBatchTime;
              for (final op in rawOps) {
                if (op is Map) {
                  int uTs = int.tryParse((op['updated_at'] ?? '0').toString()) ?? 0;
                  if (uTs > 100000000000000) uTs ~/= 1000;
                  if (uTs > _lastKnownBatchTime) {
                    freshOps.add(op);
                    if (uTs > maxBatchTs) maxBatchTs = uTs;
                  }
                }
              }
              if (freshOps.isNotEmpty) {
                final cbResult = await onBatchReceived?.call(freshOps);
                if (cbResult != false) {
                  _lastKnownBatchTime = maxBatchTs;
                }
              }
            }

            // 🔔 Process all new Signal Events (mutations array + latest event) chronologically without OUTBOX_BATCH masking
            final List<Map<String, dynamic>> candidateEvents = [];
            if (data['mutations'] is List) {
              for (final m in (data['mutations'] as List)) {
                if (m is Map) {
                  candidateEvents.add(Map<String, dynamic>.from(m));
                }
              }
            }
            if (data['event'] is Map) {
              candidateEvents.add(Map<String, dynamic>.from(data['event'] as Map));
            }

            final agg = aggregateRemoteSignals(
              rawEvents: candidateEvents,
              mySource: cleanSource,
              lastSeenTs: _lastKnownSignalTime,
            );
            _lastKnownSignalTime = agg.maxTimestamp;

            if (agg.mergedEvent != null) {
              final mergedEvent = agg.mergedEvent!;
              debugPrint("⚡ [CloudSignalChannel] Remote Real Mutation Received from ${mergedEvent.source}: ${mergedEvent.action} (del:${mergedEvent.deletedIds.length}, unmark:${mergedEvent.unmarkedIds.length})");
              await onSignal(mergedEvent);
            }
          }
        }
      } catch (_) {
        // Silent catch for resilience
      } finally {
        _isChecking = false;
      }
    });
  }

  void stopListening() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isChecking = false;
  }
}
