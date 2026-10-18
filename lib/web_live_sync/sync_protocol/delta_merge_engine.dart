import "../../../sync_core/d1_sales_ledger_service.dart";
// FILE: lib/web_live_sync/sync_protocol/delta_merge_engine.dart
import 'dart:convert';
import '../../../pharoah_manager.dart';
import '../../../models.dart';
import '../../sync_core/modules/purchase_sync_module.dart';

/// 🛡️ THE ENHANCED DELTA MERGE ENGINE RECONCILER
/// Bridges Google Drive snapshots and D1 JSON batch inputs without ghost overwrites.
class DeltaMergeEngine {
  /// 🛡️ Dedicated Incoming Delta Batch Merger for Sales
  static List<Sale> mergeIncomingDelta({
    required List<Sale> localList,
    required List<dynamic> incomingCloudBatch,
    required Map<String, int> localTombstoneRegistry,
  }) {
    for (var rawCloudMap in incomingCloudBatch) {
      if (rawCloudMap is! Map<String, dynamic>) continue;
      final cloudMap = rawCloudMap;
      String syncId = (cloudMap['sync_id'] ?? cloudMap['id'] ?? '').toString().trim();
      int cloudVersion = int.tryParse(cloudMap['version']?.toString() ?? '1') ?? 1;
      int cloudTimestamp = int.tryParse(cloudMap['updated_at']?.toString() ?? cloudMap['updatedAt']?.toString() ?? '0') ?? 0;
      int cloudIsDeleted = int.tryParse(cloudMap['is_deleted']?.toString() ?? cloudMap['isDeleted']?.toString() ?? (cloudMap['status'] == 'Deleted' || cloudMap['status'] == 'Cancelled' ? '1' : '0')) ?? 0;

      if (syncId.isEmpty) continue;
      String billNo = (cloudMap['billNo'] ?? cloudMap['internalNo'] ?? '').toString().trim();
      String cleanBill = billNo.toUpperCase();
      if (D1SalesLedgerService.isBillDeleted(syncId, billNo)) continue;

      // 🛡️ SHIELD 1: Anti-Zombie Tombstone Check
      if (localTombstoneRegistry.containsKey(syncId) || (cleanBill.isNotEmpty && localTombstoneRegistry.containsKey(cleanBill))) {
        continue; // Dropped securely, never resurrect from lagging cloud packet
      }

      int idx = localList.indexWhere((s) => s.syncId == syncId || s.id == syncId || (cleanBill.isNotEmpty && s.billNo.trim().toUpperCase() == cleanBill));

      if (idx != -1) {
        Sale localSale = localList[idx];
        if (cloudIsDeleted == 1) {
          localList.removeAt(idx);
          localTombstoneRegistry[syncId] = cloudTimestamp > 0 ? cloudTimestamp : DateTime.now().millisecondsSinceEpoch;
          if (cleanBill.isNotEmpty) localTombstoneRegistry[cleanBill] = localTombstoneRegistry[syncId]!;
        } else if (cloudVersion > localSale.version || (cloudVersion == localSale.version && cloudTimestamp >= localSale.updatedAt) || localSale.updatedAt == 0) {
          localList[idx] = Sale.fromEnvelope(cloudMap);
        }
      } else {
        if (cloudIsDeleted == 0) {
          if (cleanBill.isNotEmpty) {
            localList.removeWhere((s) => s.billNo.trim().toUpperCase() == cleanBill && s.updatedAt <= cloudTimestamp);
          }
          localList.insert(0, Sale.fromEnvelope(cloudMap));
        }
      }
    }
    return localList;
  }

  /// 🛡️ Smartly merges cloud snapshot data with ERP Multi-Node collision prevention,
  /// Anti-Zombie Multi-Key Shields, and True LWW safeguards.
  static bool processCloudData(
    PharoahManager ph, 
    Map<String, dynamic> cloudFiles, 
    dynamic localTombstonesOrRegistry, 
    Map<String, String> localHashes
  ) {
    bool hasChanges = false;
    final int nowEpoch = DateTime.now().millisecondsSinceEpoch;
    Map<String, int> tombstoneRegistry = {};
    if (localTombstonesOrRegistry is Map<String, int>) {
      tombstoneRegistry = Map<String, int>.from(localTombstonesOrRegistry);
    } else if (localTombstonesOrRegistry is Set<String>) {
      for (var k in localTombstonesOrRegistry) {
        tombstoneRegistry[k] = nowEpoch;
      }
    } else if (localTombstonesOrRegistry is Iterable) {
      for (var k in localTombstonesOrRegistry) {
        tombstoneRegistry[k.toString()] = nowEpoch;
      }
    }

    dynamic decodeJson(String fileName) {
      if (cloudFiles.containsKey(fileName) && cloudFiles[fileName] != null) {
        try { return jsonDecode(cloudFiles[fileName]); } catch (_) {}
      }
      return null;
    }

    // 🛡️ 0. MASTER RECORDS (PARTIES & MEDICINES) MERGE FIRST TO ENSURE FOREIGN KEY INTEGRITY
    return hasChanges || cSales || cPurc || cVouc || cSCh || cPCh || cSRet || cPRet;
  }
}
