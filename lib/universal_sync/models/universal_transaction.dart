// FILE: lib/universal_sync/models/universal_transaction.dart
// Live Revision: #PH-REV-695 (UNIVERSAL-MULTI-TAB-EDGE-CONCURRENCY-PRO)
import "dart:convert";

/// UniversalTransaction: Unified polymorphic transaction envelope for all ERP documents.
/// Provides immutable GUID identity, monotonic versioning, and zero-flicker payload transport.
class UniversalTransaction {
  final String guid;
  final String docType; // "SALE", "PURCHASE", "CHALLAN", "PURCHASE_CHALLAN", "CREDIT_NOTE", "DEBIT_NOTE", "VOUCHER"
  final int version;
  final int seq;
  final int updatedAt;
  final int isDeleted;
  final String clientSource;
  final Map<String, dynamic> payload;

  const UniversalTransaction({
    required this.guid,
    required this.docType,
    required this.version,
    required this.seq,
    required this.updatedAt,
    required this.isDeleted,
    required this.clientSource,
    required this.payload,
  });

  Map<String, dynamic> toMap() {
    return {
      "guid": guid,
      "docType": docType,
      "version": version,
      "seq": seq,
      "updatedAt": updatedAt,
      "isDeleted": isDeleted,
      "clientSource": clientSource,
      "payload": payload,
    };
  }

  factory UniversalTransaction.fromMap(Map<String, dynamic> map) {
    return UniversalTransaction(
      guid: (map["guid"] ?? map["id"] ?? map["syncId"] ?? "").toString().trim(),
      docType: (map["docType"] ?? map["documentType"] ?? "SALE").toString().trim().toUpperCase(),
      version: int.tryParse(map["version"]?.toString() ?? "1") ?? 1,
      seq: int.tryParse(map["seq"]?.toString() ?? "0") ?? 0,
      updatedAt: int.tryParse(map["updatedAt"]?.toString() ?? map["updated_at"]?.toString() ?? "0") ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: int.tryParse(map["isDeleted"]?.toString() ?? map["is_deleted"]?.toString() ?? "0") ?? (map["status"] == "Deleted" ? 1 : 0),
      clientSource: (map["clientSource"] ?? map["source"] ?? "UNKNOWN").toString().trim(),
      payload: map["payload"] is Map<String, dynamic> 
          ? Map<String, dynamic>.from(map["payload"]) 
          : Map<String, dynamic>.from(map),
    );
  }

  String toJson() => jsonEncode(toMap());
}
