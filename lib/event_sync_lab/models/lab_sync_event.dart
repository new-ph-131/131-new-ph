// FILE: lib/event_sync_lab/models/lab_sync_event.dart
import 'dart:convert';

/// Strict Event Data Model for Event-Driven 2-Way Sync Bus
class LabSyncEvent {
  final String id;
  final String storeToken;
  final String source; // 'APP' or 'WEB'
  final String action; // 'SALE_SAVED', 'SALE_DELETED', 'PURCHASE_SAVED', etc.
  final String entityId;
  final int timestamp;
  final Map<String, dynamic> payload;

  LabSyncEvent({
    required this.id,
    required this.storeToken,
    required this.source,
    required this.action,
    required this.entityId,
    required this.timestamp,
    this.payload = const {},
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'storeToken': storeToken,
    'source': source,
    'action': action,
    'entityId': entityId,
    'timestamp': timestamp,
    'payload': payload,
  };

  factory LabSyncEvent.fromMap(Map<String, dynamic> map) => LabSyncEvent(
    id: map['id']?.toString() ?? '',
    storeToken: (map['storeToken']?.toString() ?? '').trim().toUpperCase(),
    source: (map['source']?.toString() ?? 'UNKNOWN').toUpperCase(),
    action: map['action']?.toString() ?? 'DELTA_MUTATION',
    entityId: map['entityId']?.toString() ?? '',
    timestamp: map['timestamp'] is int
        ? map['timestamp']
        : int.tryParse(map['timestamp']?.toString() ?? '0') ?? DateTime.now().millisecondsSinceEpoch,
    payload: map['payload'] is Map ? Map<String, dynamic>.from(map['payload']) : {},
  );

  String toJson() => jsonEncode(toMap());
  factory LabSyncEvent.fromJson(String str) => LabSyncEvent.fromMap(jsonDecode(str));

  bool isFromPeer(String mySource) => source.toUpperCase() != mySource.toUpperCase();
}
