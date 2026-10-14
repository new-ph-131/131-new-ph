// FILE: lib/universal_sync/engine/universal_d1_hot_engine.dart
// Live Revision: #PH-REV-695 (UNIVERSAL-MULTI-TAB-EDGE-CONCURRENCY-PRO)
import "dart:async";
import "dart:convert";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "../models/universal_transaction.dart";
import "../coordinator/tab_session_coordinator.dart";
import "universal_reactive_store.dart";

/// UniversalD1HotEngine: Direct edge ledger communicator.
/// Bypasses slow Google Drive snapshots during real-time transactions.
class UniversalD1HotEngine {
  static final UniversalD1HotEngine instance = UniversalD1HotEngine._internal();
  UniversalD1HotEngine._internal();

  static const String endpoint = "https://pharoah-erp.pages.dev/api/lab_signal";
  static Timer? _pollTimer;
  static int _lastSeq = 0;

  /// Starts listening for real-time edge transactions
  static void startListening({
    required String storeToken,
    required Function(UniversalTransaction) onTransactionReceived,
    Duration interval = const Duration(milliseconds: 3000),
  }) {
    stopListening();
    if (storeToken.trim().isEmpty) return;

    _pollTimer = Timer.periodic(interval, (_) async {
      final txList = await _fetchDeltas(storeToken);
      for (final tx in txList) {
        if (!TabSessionCoordinator.isSelfOrigin(tx.clientSource)) {
          onTransactionReceived(tx);
        }
      }
    });
  }

  static void stopListening() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  static Future<List<UniversalTransaction>> _fetchDeltas(String storeToken) async {
    try {
      final uri = Uri.parse("$endpoint?storeToken=${Uri.encodeComponent(storeToken.trim().toUpperCase())}&since_seq=$_lastSeq");
      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["status"] == "SUCCESS" && data["transactions"] is List) {
          final rawList = data["transactions"] as List;
          final List<UniversalTransaction> result = [];
          for (final item in rawList) {
            if (item is Map<String, dynamic>) {
              final tx = UniversalTransaction.fromMap(item);
              result.add(tx);
              if (tx.seq > _lastSeq) _lastSeq = tx.seq;
            }
          }
          return result;
        }
      }
    } catch (_) {}
    return [];
  }
}
