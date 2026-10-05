// FILE: lib/realtime_signaling/models/sync_signal_event.dart
import 'dart:convert';

/// Represents an instantaneous real-time sync signal between App and Web.
class SyncSignalEvent {
  final String storeToken;
  final String source; // 'app' | 'web'
  final String action; // 'BILL_CREATED' | 'VOUCHER_SAVED' | 'CHALLAN_SAVED' | 'RECORD_DELETED' | 'BULK_DELETE' | 'DATA_SYNC'
  final String entityId;
  final int timestamp;
  final String companyId;
  final List<String> deletedIds;
  final dynamic delta;

  SyncSignalEvent({
    required this.storeToken,
    required this.source,
    required this.action,
    this.entityId = '',
    int? timestamp,
    this.companyId = '',
    this.deletedIds = const [],
    this.delta,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
    'storeToken': storeToken,
    'source': source,
    'action': action,
    'entityId': entityId,
    'timestamp': timestamp,
    'companyId': companyId,
    'deletedIds': deletedIds,
    'delta': delta,
  };

  String toJson() => jsonEncode(toMap());

  factory SyncSignalEvent.fromMap(Map<String, dynamic> map) {
    return SyncSignalEvent(
      storeToken: (map['storeToken'] ?? '').toString(),
      source: (map['source'] ?? '').toString(),
      action: (map['action'] ?? 'DATA_SYNC').toString(),
      entityId: (map['entityId'] ?? '').toString(),
      timestamp: int.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
      companyId: (map['companyId'] ?? '').toString(),
      deletedIds: (map['deletedIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
      delta: map['delta'],
    );
  }

  factory SyncSignalEvent.fromJson(String source) {
    try {
      return SyncSignalEvent.fromMap(jsonDecode(source));
    } catch (_) {
      return SyncSignalEvent(storeToken: '', source: 'unknown', action: 'DATA_SYNC');
    }
  }
}
