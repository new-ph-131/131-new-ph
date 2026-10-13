import 'package:flutter_test/flutter_test.dart';
import 'package:pharoah_erp/sync_bridge/core/sync_identity_guard.dart';
import 'package:pharoah_erp/sync_bridge/core/sync_tombstone_hub.dart';
import 'package:pharoah_erp/sync_bridge/engines/universal_delta_merger.dart';
import 'package:pharoah_erp/models.dart';

void main() {
  test('2-Way Sync Engine: ID Lock, Tombstone & In-Place Merge Test', () {
    const originalId = "SALE-101-ORIGINAL";
    final resolved = SyncIdentityGuard.resolveId(
      existingId: originalId,
      prefix: "INV",
      referenceNo: "INV-101",
    );
    expect(resolved, equals(originalId));

    final tombstones = {"DEL-001", "INV-999"};
    expect(SyncTombstoneHub.isDeleted(tombstones, "DEL-001"), isTrue);
    expect(SyncTombstoneHub.isDeleted(tombstones, "random-id", referenceNo: "INV-999"), isTrue);
    expect(SyncTombstoneHub.isDeleted(tombstones, "ACTIVE-001"), isFalse);

    final localSales = [
      Sale(
        id: "SALE-MERGE-TEST-101",
        billNo: "INV-MERGE-TEST-101",
        partyId: "P1",
        date: DateTime.utc(2025, 1, 1),
        partyName: "Test Party",
        partyGstin: "N/A",
        partyState: "Rajasthan",
        items: [],
        totalAmount: 100.0,
        paymentMode: "CASH",
      )
    ];

    final cloudIncoming = [
      {
        "id": "SALE-MERGE-TEST-101",
        "billNo": "INV-MERGE-TEST-101",
        "partyId": "P1",
        "date": DateTime.utc(2025, 1, 1).toIso8601String(),
        "partyName": "Test Party",
        "partyGstin": "N/A",
        "partyState": "Rajasthan",
        "items": [],
        "totalAmount": 250.0,
        "paymentMode": "CASH",
        "updatedAt": 2000,
        "version": 2,
      }
    ];

    final changed = UniversalDeltaMerger.mergeEntityList<Sale>(
      cloudList: cloudIncoming,
      localList: localSales,
      tombstones: tombstones,
      getId: (s) => s.id,
      getRefNo: (s) => s.billNo,
      fromMap: (m) => Sale.fromMap(m),
      toMap: (s) => s.toMap(),
    );

    expect(changed, isTrue);
    expect(localSales.first.totalAmount, equals(250.0));
    expect(localSales.length, equals(1));
  });
}
