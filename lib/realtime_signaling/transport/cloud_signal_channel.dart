// FILE: lib/realtime_signaling/transport/cloud_signal_channel.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/sync_signal_event.dart';
import '../../web_live_sync/web_cloud_config.dart';

/// CloudSignalChannel: Low-latency event signaling bus between App & Web.
/// Delivers wake-up coordination signals in milliseconds without transmitting heavy files.
class CloudSignalChannel {
  static final CloudSignalChannel instance = CloudSignalChannel._internal();
  CloudSignalChannel._internal();

  Timer? _pollTimer;
  int _lastKnownSignalTime = 0;
  bool _isChecking = false;

  /// Broadcasts a fast wake-up signal to Cloud Relay
  Future<bool> broadcastSignal(SyncSignalEvent event) async {
    try {
      if (event.storeToken.isEmpty) return false;
      
      final payload = {
        "action": "BROADCAST_SIGNAL",
        "storeToken": event.storeToken,
        "source": event.source,
        "signalAction": event.action,
        "entityId": event.entityId,
        "companyId": event.companyId,
        "timestamp": event.timestamp,
      };

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(WebCloudConfig.cloudRelayEndpoint))
        ..headers.addAll(WebCloudConfig.standardHeaders)
        ..body = jsonEncode(payload)
        ..followRedirects = true;

      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse);
      return response.statusCode == 200 || response.body.contains("SUCCESS");
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
    Duration interval = const Duration(seconds: 3),
  }) {
    stopListening();
    if (storeToken.isEmpty) return;

    _lastKnownSignalTime = DateTime.now().millisecondsSinceEpoch;

    _pollTimer = Timer.periodic(interval, (_) async {
      if (_isChecking) return;
      _isChecking = true;
      try {
        final uri = Uri.parse(
          "${WebCloudConfig.cloudRelayEndpoint}?action=GET_SIGNAL"
          "&storeToken=${Uri.encodeComponent(storeToken)}"
          "&since=$_lastKnownSignalTime"
        );

        final response = await http.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200 && !response.body.contains("ERROR")) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'SUCCESS' && data['signal'] != null) {
            final event = SyncSignalEvent.fromMap(data['signal']);
            if (event.timestamp > _lastKnownSignalTime && event.source != mySource) {
              _lastKnownSignalTime = event.timestamp;
              debugPrint("⚡ [CloudSignalChannel] Incoming signal received from ${event.source}: ${event.action}");
              onSignal(event);
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
