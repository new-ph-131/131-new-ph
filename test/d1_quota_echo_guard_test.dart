import 'package:flutter_test/flutter_test.dart';
import 'package:pharoah_erp/realtime_signaling/models/sync_signal_event.dart';
import 'package:pharoah_erp/realtime_signaling/transport/cloud_signal_channel.dart';

void main() {
  test('SyncSignalEvent preserves deviceId across serialization', () {
    final evt = SyncSignalEvent(
      storeToken: 'TK1',
      source: 'OUTBOX_BATCH',
      action: 'JSON_BATCH_MUTATION',
      deviceId: 'MREG-DEVICE-1234',
      timestamp: 5000,
    );
    final decoded = SyncSignalEvent.fromMap(evt.toMap());
    expect(decoded.deviceId, equals('MREG-DEVICE-1234'));
    expect(decoded.source, equals('OUTBOX_BATCH'));
  });

  test('CloudSignalChannel skips self OUTBOX_BATCH echo while accepting peer OUTBOX_BATCH', () {
    final aggSelfOnly = CloudSignalChannel.aggregateRemoteSignals(
      rawEvents: [
        {
          'id': 'ev-self',
          'storeToken': 'TK1',
          'source': 'OUTBOX_BATCH',
          'action': 'JSON_BATCH_MUTATION',
          'deviceId': 'APP-DEV-1',
          'timestamp': 2000,
          'deletedIds': ['SALE-1'],
        },
      ],
      mySource: 'app',
      lastSeenTs: 1000,
      myDeviceId: 'APP-DEV-1',
    );
    expect(aggSelfOnly.mergedEvent, isNull);
    expect(aggSelfOnly.maxTimestamp, equals(2000));

    final aggPeer = CloudSignalChannel.aggregateRemoteSignals(
      rawEvents: [
        {
          'id': 'ev-self',
          'storeToken': 'TK1',
          'source': 'OUTBOX_BATCH',
          'action': 'JSON_BATCH_MUTATION',
          'deviceId': 'APP-DEV-1',
          'timestamp': 2000,
          'deletedIds': ['SALE-1'],
        },
        {
          'id': 'ev-peer',
          'storeToken': 'TK1',
          'source': 'OUTBOX_BATCH',
          'action': 'JSON_BATCH_MUTATION',
          'deviceId': 'WEB-DEV-9',
          'timestamp': 2500,
          'unmarkedIds': ['SALE-2'],
        },
      ],
      mySource: 'app',
      lastSeenTs: 1000,
      myDeviceId: 'APP-DEV-1',
    );
    expect(aggPeer.mergedEvent, isNotNull);
    expect(aggPeer.mergedEvent!.deviceId, equals('WEB-DEV-9'));
    expect(aggPeer.mergedEvent!.unmarkedIds, contains('SALE-2'));
    expect(aggPeer.mergedEvent!.deletedIds, isEmpty);
    expect(aggPeer.maxTimestamp, equals(2500));
  });
}
