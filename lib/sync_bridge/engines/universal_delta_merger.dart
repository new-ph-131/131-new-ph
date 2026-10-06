import 'dart:convert';
import 'package:pharoah_erp/models.dart';
import '../core/sync_tombstone_hub.dart';

/// UniversalDeltaMerger: Handles smart, bidirectional, conflict-free merging
/// between Cloud Relay and local device data for all transaction entities.
class UniversalDeltaMerger {
  /// Merges cloud JSON lists into local memory lists while strictly respecting tombstones.
  static bool mergeEntityList<T>({
    required List<dynamic>? cloudList,
    required List<T> localList,
    required Set<String> tombstones,
    required String Function(T) getId,
    required String Function(T) getRefNo,
    required T Function(Map<String, dynamic>) fromMap,
    required Map<String, dynamic> Function(T) toMap,
  }) {
    if (cloudList == null) return false;
    bool hasChanged = false;

    // 1. Purge any locally present item that exists in tombstones
    final initialLen = localList.length;
    localList.removeWhere((item) =>
        SyncTombstoneHub.isDeleted(tombstones, getId(item), referenceNo: getRefNo(item)));
    if (localList.length != initialLen) {
      hasChanged = true;
    }

    // 2. Process incoming cloud items
    for (final raw in cloudList) {
      if (raw is! Map<String, dynamic>) continue;
      final cloudMap = raw;
      final id = (cloudMap['id'] ?? '').toString().trim();
      final refNo = (cloudMap['billNo'] ?? cloudMap['internalNo'] ?? cloudMap['voucherNo'] ?? '').toString().trim();

      if (id.isEmpty) continue;

      // Skip if marked deleted
      if (SyncTombstoneHub.isDeleted(tombstones, id, referenceNo: refNo)) {
        continue;
      }

      final existingIdx = localList.indexWhere((item) => getId(item) == id);

      if (existingIdx == -1) {
        // New record from cloud: Add to local list
        localList.add(fromMap(cloudMap));
        hasChanged = true;
      } else {
        // Existing record: Check if data differs
        final localJson = jsonEncode(toMap(localList[existingIdx]));
        final cloudJson = jsonEncode(cloudMap);
        if (localJson != cloudJson) {
          final cloudUpdatedAt = (cloudMap['updatedAt'] ?? 0) as int;
          final cloudVersion = (cloudMap['version'] ?? 1) as int;
          final localItemMap = toMap(localList[existingIdx]);
          final localUpdatedAt = (localItemMap['updatedAt'] ?? 0) as int;
          final localVersion = (localItemMap['version'] ?? 1) as int;

          // LWW: Only overwrite if cloud record is newer or same time with higher/equal version
          if (cloudUpdatedAt > localUpdatedAt || (cloudUpdatedAt == localUpdatedAt && cloudVersion >= localVersion) || localUpdatedAt == 0) {
            localList[existingIdx] = fromMap(cloudMap);
            hasChanged = true;
          }
        }
      }
    }

    return hasChanged;
  }

  /// Full sync orchestrator across all core ERP collections
  static bool reconcileAllCollections({
    required Map<String, dynamic> cloudFiles,
    required Set<String> tombstones,
    required List<Sale> sales,
    required List<Purchase> purchases,
    required List<Voucher> vouchers,
    required List<SaleChallan> saleChallans,
    required List<PurchaseChallan> purchaseChallans,
    required List<SaleReturn> saleReturns,
    required List<PurchaseReturn> purchaseReturns,
  }) {
    dynamic decodeJson(String fileName) {
      if (cloudFiles.containsKey(fileName) && cloudFiles[fileName] != null) {
        try {
          return jsonDecode(cloudFiles[fileName]);
        } catch (_) {}
      }
      return null;
    }

    bool c1 = mergeEntityList<Sale>(
      cloudList: decodeJson('sales.json'),
      localList: sales,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => e.billNo,
      fromMap: (m) => Sale.fromMap(m),
      toMap: (e) => e.toMap(),
    );

    bool c2 = mergeEntityList<Purchase>(
      cloudList: decodeJson('purc.json'),
      localList: purchases,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => e.internalNo.isNotEmpty ? e.internalNo : e.billNo,
      fromMap: (m) => Purchase.fromMap(m),
      toMap: (e) => e.toMap(),
    );

    bool c3 = mergeEntityList<Voucher>(
      cloudList: decodeJson('vouc.json'),
      localList: vouchers,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => e.voucherNo,
      fromMap: (m) => Voucher.fromMap(m),
      toMap: (e) => e.toMap(),
    );

    bool c4 = mergeEntityList<SaleChallan>(
      cloudList: decodeJson('s_challan.json'),
      localList: saleChallans,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => e.billNo,
      fromMap: (m) => SaleChallan.fromMap(m),
      toMap: (e) => e.toMap(),
    );

    bool c5 = mergeEntityList<PurchaseChallan>(
      cloudList: decodeJson('p_challan.json'),
      localList: purchaseChallans,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => e.internalNo.isNotEmpty ? e.internalNo : e.billNo,
      fromMap: (m) => PurchaseChallan.fromMap(m),
      toMap: (e) => e.toMap(),
    );

    bool c6 = mergeEntityList<SaleReturn>(
      cloudList: decodeJson('s_return.json'),
      localList: saleReturns,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => e.billNo,
      fromMap: (m) => SaleReturn.fromMap(m),
      toMap: (e) => e.toMap(),
    );

    bool c7 = mergeEntityList<PurchaseReturn>(
      cloudList: decodeJson('p_return.json'),
      localList: purchaseReturns,
      tombstones: tombstones,
      getId: (e) => e.id,
      getRefNo: (e) => e.billNo,
      fromMap: (m) => PurchaseReturn.fromMap(m),
      toMap: (e) => e.toMap(),
    );

    return c1 || c2 || c3 || c4 || c5 || c6 || c7;
  }
}
