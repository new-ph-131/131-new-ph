// FILE: lib/event_sync_lab/method/lab_event_transport.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/lab_sync_event.dart';

/// Transport Layer for Event-Driven 2-Way Sync Bus
class LabEventTransport {
  static final LabEventTransport instance = LabEventTransport._internal();
  LabEventTransport._internal();

  static const String edgeSignalEndpoint = "https://pharoah-erp.pages.dev/api/lab_signal";

  String connectionStatus = "IDLE"; // 'IDLE', 'CONNECTED', 'LISTENING', 'ERROR'
  int lastLatencyMs = 0;
  int totalSignalsSent = 0;
  int totalSignalsReceived = 0;
  int totalDriveCallsSaved = 0;

  Timer? _edgeListenTimer;
  int _lastSeenTimestamp = 0;
  String _activeStoreToken = "";
  String _mySource = "APP"; // 'APP' or 'WEB'
  void Function(LabSyncEvent event)? _onSignalCallback;

  /// Emits an event into the Realtime Bus (<100ms)
  Future<bool> emitSignal(LabSyncEvent event) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http.post(
        Uri.parse(edgeSignalEndpoint),
        headers: {"Content-Type": "application/json"},
        body: event.toJson(),
      ).timeout(const Duration(seconds: 5));

      stopwatch.stop();
      lastLatencyMs = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200) {
        totalSignalsSent++;
        debugPrint("⚡ [LabEventTransport] Signal Emitted in ${lastLatencyMs}ms: ${event.action} (${event.source})");
        return true;
      }
      return false;
    } catch (e) {
      stopwatch.stop();
      debugPrint("⚠ [LabEventTransport] Signal Emit Failed: $e");
      return false;
    }
  }

  /// Starts listening to signals for this store
  void startListening({
    required String storeToken,
    required String mySource,
    required void Function(LabSyncEvent event) onSignal,
  }) {
    stopListening();
    _activeStoreToken = storeToken.trim().toUpperCase();
    _mySource = mySource.trim().toUpperCase();
    _onSignalCallback = onSignal;
    _lastSeenTimestamp = DateTime.now().millisecondsSinceEpoch;
    connectionStatus = "CONNECTED";

    debugPrint("🟢 [LabEventTransport] Started Event Listener for $_activeStoreToken (Role: $_mySource)");

    // Ultra-lightweight edge ping check (10-byte micro payload on Cloudflare Edge, 0 Google Drive calls)
    _edgeListenTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      await _checkEdgeUpdate();
    });
  }

  Future<void> _checkEdgeUpdate() async {
    if (_activeStoreToken.isEmpty || _onSignalCallback == null) return;
    try {
      final uri = Uri.parse(
        "$edgeSignalEndpoint?storeToken=${Uri.encodeComponent(_activeStoreToken)}"
        "&lastSeenTs=$_lastSeenTimestamp"
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      
      // Every successful check that finds no mutation means we SAVED a heavy 2MB Google Drive request!
      totalDriveCallsSaved++;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['status'] == 'SUCCESS' && data['hasUpdate'] == true && data['event'] != null) {
          final event = LabSyncEvent.fromMap(data['event']);
          
          // Verify it is from the PEER (ignore our own echo)
          if (event.timestamp > _lastSeenTimestamp && event.isFromPeer(_mySource)) {
            _lastSeenTimestamp = event.timestamp;
            totalSignalsReceived++;
            debugPrint("🔔 [LabEventTransport] Remote Peer Event Received: ${event.action} from ${event.source}!");
            _onSignalCallback!(event);
          } else {
            // Update timestamp so we don't re-trigger
            if (event.timestamp > _lastSeenTimestamp) {
              _lastSeenTimestamp = event.timestamp;
            }
          }
        }
        connectionStatus = "CONNECTED";
      }
    } catch (e) {
      connectionStatus = "RECONNECTING";
    }
  }

  /// Stops the listener
  void stopListening() {
    _edgeListenTimer?.cancel();
    _edgeListenTimer = null;
    connectionStatus = "IDLE";
    debugPrint("🛑 [LabEventTransport] Stopped Event Listener");
  }
}
