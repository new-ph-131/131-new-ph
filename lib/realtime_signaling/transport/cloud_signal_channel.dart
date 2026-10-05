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
    Duration interval = const Duration(milliseconds: 1200),
  }) {
    stopListening();
    if (storeToken.isEmpty) return;

    _lastKnownSignalTime = DateTime.now().millisecondsSinceEpoch;
    final cleanToken = storeToken.trim().toUpperCase();
    final cleanSource = mySource.trim().toUpperCase();

    _pollTimer = Timer.periodic(interval, (_) async {
      if (_isChecking) return;
      _isChecking = true;
      try {
        final uri = Uri.parse(
          "$edgeSignalEndpoint?storeToken=${Uri.encodeComponent(cleanToken)}"
          "&lastSeenTs=$_lastKnownSignalTime"
        );
        final response = await http.get(uri).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'SUCCESS' && data['hasUpdate'] == true && data['event'] != null) {
            final sig = data['event'];
            final event = SyncSignalEvent.fromMap(sig);
            if (event.timestamp > _lastKnownSignalTime && event.source.toUpperCase() != cleanSource) {
              _lastKnownSignalTime = event.timestamp;
              debugPrint("⚡ [CloudSignalChannel] Remote Real Mutation Received from ${event.source}: ${event.action}");
              onSignal(event);
            } else if (event.timestamp > _lastKnownSignalTime) {
              _lastKnownSignalTime = event.timestamp;
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
