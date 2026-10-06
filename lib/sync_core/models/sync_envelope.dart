// FILE: lib/sync_core/models/sync_envelope.dart
import 'dart:convert';

/// SyncEnvelope: Standardized event container for transaction outbox & D1 replication.
class SyncEnvelope {
  final String syncId;
  final String storeToken;
  final String documentType; // 'SALE', 'PURCHASE', 'CHALLAN', 'VOUCHER', etc.
  final int version;
  final int updatedAt; // High-precision microsecond or millisecond epoch
  final int isDeleted; // 0 = Active, 1 = Soft Deleted
  final Map<String, dynamic> billData;

  SyncEnvelope({
    required this.syncId,
    this.storeToken = '',
    required this.documentType,
    required this.version,
    required this.updatedAt,
    required this.isDeleted,
    required this.billData,
  });

  Map<String, dynamic> toMap() => {
    'sync_id': syncId,
    'store_token': storeToken,
    'document_type': documentType,
    'version': version,
    'updated_at': updatedAt,
    'is_deleted': isDeleted,
    'bill_data': billData,
  };

  String toJson() => jsonEncode(toMap());

  factory SyncEnvelope.fromMap(Map<String, dynamic> map) {
    dynamic rawData = map['bill_data'];
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

    return SyncEnvelope(
      syncId: (map['sync_id'] ?? '').toString(),
      storeToken: (map['store_token'] ?? '').toString(),
      documentType: (map['document_type'] ?? 'SALE').toString().toUpperCase(),
      version: int.tryParse(map['version']?.toString() ?? '1') ?? 1,
      updatedAt: int.tryParse(map['updated_at']?.toString() ?? '0') ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: int.tryParse(map['is_deleted']?.toString() ?? '0') ?? 0,
      billData: parsedData,
    );
  }

  factory SyncEnvelope.fromJson(String jsonStr) =>
      SyncEnvelope.fromMap(jsonDecode(jsonStr));
}
