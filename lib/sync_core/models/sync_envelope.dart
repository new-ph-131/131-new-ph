// FILE: lib/sync_core/models/sync_envelope.dart
import 'dart:convert';

/// SyncEnvelope: Standardized event container for transaction outbox & D1 replication.
/// Fully compatible with Step 4 JSON Batch Format with sequential ordering and action tagging.
class SyncEnvelope {
  final int seq;
  final String syncId;
  final String storeToken;
  final String documentType; // 'SALE', 'PURCHASE', 'CHALLAN', 'VOUCHER', etc.
  final String action; // 'INSERT', 'UPDATE', 'DELETE'
  final String deviceId;
  final int version;
  final int updatedAt; // High-precision microsecond or millisecond epoch
  final int isDeleted; // 0 = Active, 1 = Soft Deleted
  final Map<String, dynamic> billData;

  SyncEnvelope({
    this.seq = 0,
    required this.syncId,
    this.storeToken = '',
    required this.documentType,
    this.action = 'UPDATE',
    this.deviceId = '',
    required this.version,
    required this.updatedAt,
    required this.isDeleted,
    required this.billData,
  });

  Map<String, dynamic> toMap() => {
    'seq': seq,
    'sync_id': syncId,
    'store_token': storeToken,
    'document_type': documentType,
    'action': action,
    'device_id': deviceId,
    'version': version,
    'updated_at': updatedAt,
    'is_deleted': isDeleted,
    'data': billData,
    'bill_data': billData,
  };

  String toJson() => jsonEncode(toMap());

  factory SyncEnvelope.fromMap(Map<String, dynamic> map) {
    dynamic rawData = map['data'] ?? map['bill_data'];
    Map<String, dynamic> parsedData;
    if (rawData is String) {
      try {
        parsedData = jsonDecode(rawData);
      } catch (_) {
        parsedData = {};
      }
    } else if (rawData is Map) {
      parsedData = Map<String, dynamic>.from(rawData);
    } else {
      parsedData = {};
    }

    final int parsedDeleted = int.tryParse(map['is_deleted']?.toString() ?? '0') ??
        ((map['action']?.toString().toUpperCase() == 'DELETE') ? 1 : 0);

    return SyncEnvelope(
      seq: int.tryParse(map['seq']?.toString() ?? '0') ?? 0,
      syncId: (map['sync_id'] ?? '').toString(),
      storeToken: (map['store_token'] ?? '').toString(),
      documentType: (map['document_type'] ?? 'SALE').toString().toUpperCase(),
      action: (map['action'] ?? (parsedDeleted == 1 ? 'DELETE' : 'UPDATE')).toString().toUpperCase(),
      deviceId: (map['device_id'] ?? '').toString(),
      version: int.tryParse(map['version']?.toString() ?? '1') ?? 1,
      updatedAt: int.tryParse(map['updated_at']?.toString() ?? '0') ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: parsedDeleted,
      billData: parsedData,
    );
  }

  factory SyncEnvelope.fromJson(String jsonStr) =>
      SyncEnvelope.fromMap(jsonDecode(jsonStr));
}
