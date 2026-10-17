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

  /// Starts listening for incoming events from the opposite client
  void listenToSignals({
    required String storeToken,
    required String mySource, // 'app' or 'web'
    required Function(SyncSignalEvent) onSignal,
    Function(List<dynamic>)? onBatchReceived,
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
              _lastKnownBatchTime = maxBatchTs;
              if (freshOps.isNotEmpty) {
                onBatchReceived?.call(freshOps);
              }
            }

            // 🔔 Process all new Signal Events (mutations array + latest event) without OUTBOX_BATCH masking
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

            SyncSignalEvent? latestRemoteEvent;
            final Set<String> aggregatedDeletedIds = {};
            final Set<String> aggregatedUnmarkedIds = {};
            int maxSigTs = _lastKnownSignalTime;

            for (final rawEv in candidateEvents) {
              final ev = SyncSignalEvent.fromMap(rawEv);
              int evTs = ev.timestamp;
              if (evTs > 100000000000000) evTs ~/= 1000;
              if (evTs > _lastKnownSignalTime) {
                if (evTs > maxSigTs) maxSigTs = evTs;
                final src = ev.source.trim().toUpperCase();
                if (src != cleanSource) {
                  for (final d in ev.deletedIds) {
                    if (d.trim().isNotEmpty) {
                      aggregatedDeletedIds.add(d.trim());
                      aggregatedUnmarkedIds.remove(d.trim());
                      aggregatedUnmarkedIds.remove(d.trim().toUpperCase());
                    }
                  }
                  for (final u in ev.unmarkedIds) {
                    if (u.trim().isNotEmpty) {
                      aggregatedUnmarkedIds.add(u.trim());
                      aggregatedDeletedIds.remove(u.trim());
                      aggregatedDeletedIds.remove(u.trim().toUpperCase());
                    }
                  }
                  latestRemoteEvent = ev;
                }
              }
            }

            _lastKnownSignalTime = maxSigTs;

            if (latestRemoteEvent != null) {
              final mergedEvent = SyncSignalEvent(
                storeToken: latestRemoteEvent.storeToken,
                source: latestRemoteEvent.source,
                action: latestRemoteEvent.action,
                entityId: latestRemoteEvent.entityId,
                timestamp: latestRemoteEvent.timestamp,
                companyId: latestRemoteEvent.companyId,
                deletedIds: aggregatedDeletedIds.toList(),
                unmarkedIds: aggregatedUnmarkedIds.toList(),
                delta: latestRemoteEvent.delta,
              );
              debugPrint("⚡ [CloudSignalChannel] Remote Real Mutation Received from ${mergedEvent.source}: ${mergedEvent.action} (del:${mergedEvent.deletedIds.length}, unmark:${mergedEvent.unmarkedIds.length})");
              onSignal(mergedEvent);
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
