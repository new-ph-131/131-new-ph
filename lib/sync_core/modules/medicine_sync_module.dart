import "../../logic/product_integrity_service.dart";
// FILE: lib/sync_core/modules/medicine_sync_module.dart
import "dart:convert";
import "package:flutter/foundation.dart";
import "../../models.dart";
import "../../pharoah_manager.dart";
import "../models/sync_envelope.dart";
import "../outbox/sync_queue_manager.dart";
import "../d1_sales_ledger_service.dart";

/// 🛡️ ITEM / PRODUCT MASTER SYNC MODULE (#PH-REV-738)
/// Handles 360-degree all-field mirroring, LWW monotonic versioning,
/// 4-tier deduplication (ID -> SystemId -> UniqueCode/Barcode -> Composite Name+Pack+Mfg),
/// D1 Outbox integration, and Tombstone deletion shielding across App & Web.
class MedicineSyncModule {
  static String cleanString(String input) {
    return input.replaceAll(RegExp(r"[^A-Z0-9]"), "").toUpperCase();
  }

  /// Composite key combining Name, Packing, and Company for medical accuracy
  static String getCompositeKey({
    required String name,
    required String packing,
    String company = "",
  }) {
    final cName = cleanString(name);
    final cPack = cleanString(packing);
    final cComp = cleanString(company);
    if (cName.isEmpty) return "";
    return "${cName}_${cPack}_$cComp";
  }

  /// 📤 1. D1 OUTBOX ENQUEUE: Push Product Mutation directly to Cloudflare D1
  static void onMedicineSaved(Medicine med, String storeToken, {bool isDelete = false}) {
    if (storeToken.trim().isEmpty || med.id.trim().isEmpty) return;
    SyncQueueManager.enqueueMutation(
      syncId: med.id.trim(),
      storeToken: storeToken.trim().toUpperCase(),
      docType: 'MEDICINE',
      currentVersion: med.version,
      isDelete: isDelete,
      rawPayload: med.toMap(),
    );
  }

  /// 📥 2. MERGE INCOMING ENVELOPE FROM D1 BATCH
  static bool mergeIncomingMedicineEnvelope(List<Medicine> localMedList, SyncEnvelope envelope) {
    final Map<String, dynamic> medMap = envelope.billData;
    String id = envelope.syncId.trim();
    if (id.isEmpty) {
      id = (medMap["id"] ?? "").toString().trim();
    }
    String systemId = (medMap["systemId"] ?? "").toString().trim().toUpperCase();
    String uniqueCode = (medMap["uniqueCode"] ?? "").toString().trim().toUpperCase();
    String name = (medMap["name"] ?? "").toString().trim().toUpperCase();
    String packing = (medMap["packing"] ?? "").toString().trim().toUpperCase();
    String companyId = (medMap["companyId"] ?? "").toString().trim().toUpperCase();

    final String compKey = getCompositeKey(name: name, packing: packing, company: companyId);
    final String cleanNameKey = cleanString(name);

    int incomingVersion = envelope.version > 0 ? envelope.version : 1;
    int incomingTimestamp = envelope.updatedAt > 0 ? envelope.updatedAt : DateTime.now().millisecondsSinceEpoch;
    bool isDel = envelope.isDeleted == 1 || envelope.action == "DELETE";

    if (id.isEmpty && cleanNameKey.isEmpty) return false;

    // Check Permanent Tombstones
    if (D1SalesLedgerService.isBillDeleted(id, systemId, compKey)) {
      localMedList.removeWhere((m) => m.id == id || (systemId.isNotEmpty && m.systemId == systemId));
      return true;
    }

    // 4-Tier Matching in local memory
    int existingIdx = localMedList.indexWhere((m) {
      if (id.isNotEmpty && m.id == id) return true;
      if (systemId.isNotEmpty && m.systemId.trim().toUpperCase() == systemId) return true;
      if (uniqueCode.isNotEmpty && m.uniqueCode.trim().toUpperCase() == uniqueCode) return true;
      if (compKey.isNotEmpty && getCompositeKey(name: m.name, packing: m.packing, company: m.companyId) == compKey) {
        return true;
      }
      return false;
    });

    if (isDel) {
      D1SalesLedgerService.markPermanentlyDeleted(id, systemId, compKey);
      if (existingIdx != -1) {
        localMedList.removeAt(existingIdx);
        return true;
      }
      return false;
    }

    final incomingMed = Medicine.fromMap(medMap);
    incomingMed.id = id;
    incomingMed.updatedAt = incomingTimestamp;
    incomingMed.version = incomingVersion;

    if (existingIdx != -1) {
      final local = localMedList[existingIdx];
      // LWW: Update only if incoming version or timestamp is newer
      if (incomingVersion > local.version || incomingTimestamp >= local.updatedAt) {
        incomingMed.id = local.id; // preserve local primary key
        if (incomingMed.systemId.isEmpty) incomingMed.systemId = local.systemId;
        localMedList[existingIdx] = incomingMed;
        return true;
      }
      return false;
    } else {
      localMedList.add(incomingMed);
      return true;
    }
  }

  /// 🔄 3. NON-DESTRUCTIVE LWW DELTA MERGE FOR DOWNLOADED CLOUD MEDICINES
  /// Never wipes in-flight local products! Merges in-place with LWW comparison.
  static void mergeMedicineList({
    required List<dynamic> cloudMedicineList,
    required List<Medicine> localMedicineList,
    required Map<String, dynamic> tombstoneRegistry,
    required Set<String> deletedRecordIds,
  }) {
    ProductIntegrityService.deduplicateMedicineList(localMedicineList);
    final Map<String, int> localIndexMap = {};
    for (int i = 0; i < localMedicineList.length; i++) {
      final m = localMedicineList[i];
      if (m.id.isNotEmpty) localIndexMap["ID_${m.id}"] = i;
      if (m.systemId.isNotEmpty) localIndexMap["SYS_${m.systemId.trim().toUpperCase()}"] = i;
      final cKey = getCompositeKey(name: m.name, packing: m.packing, company: m.companyId);
      if (cKey.isNotEmpty) localIndexMap["COMP_$cKey"] = i;
    }

    for (var raw in cloudMedicineList) {
      if (raw == null || raw is! Map) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
      final String id = (map['id'] ?? '').toString().trim();
      final String systemId = (map['systemId'] ?? '').toString().trim().toUpperCase();
      final String name = (map['name'] ?? '').toString().trim().toUpperCase();
      final String packing = (map['packing'] ?? '').toString().trim().toUpperCase();
      final String companyId = (map['companyId'] ?? '').toString().trim().toUpperCase();
      final String compKey = getCompositeKey(name: name, packing: packing, company: companyId);

      // Check deletion & tombstones
      if (deletedRecordIds.contains(id) ||
          (systemId.isNotEmpty && deletedRecordIds.contains(systemId)) ||
          tombstoneRegistry.containsKey(id) ||
          D1SalesLedgerService.isBillDeleted(id, systemId, compKey)) {
        localMedicineList.removeWhere((m) => m.id == id || (systemId.isNotEmpty && m.systemId == systemId));
        continue;
      }

      int existingIdx = -1;
      if (id.isNotEmpty && localIndexMap.containsKey("ID_$id")) {
        existingIdx = localIndexMap["ID_$id"]!;
      } else if (systemId.isNotEmpty && localIndexMap.containsKey("SYS_$systemId")) {
        existingIdx = localIndexMap["SYS_$systemId"]!;
      } else if (compKey.isNotEmpty && localIndexMap.containsKey("COMP_$compKey")) {
        existingIdx = localIndexMap["COMP_$compKey"]!;
      }

      final Medicine cloudMed = Medicine.fromMap(map);
      int cloudVer = (map['version'] ?? 1).toInt();
      int cloudTs = (map['updatedAt'] ?? 0).toInt();

      if (existingIdx != -1 && existingIdx < localMedicineList.length) {
        final local = localMedicineList[existingIdx];
        if (cloudVer > local.version || cloudTs >= local.updatedAt) {
          cloudMed.id = local.id;
          if (cloudMed.systemId.isEmpty) cloudMed.systemId = local.systemId;
          localMedicineList[existingIdx] = cloudMed;
        }
      } else {
        localMedicineList.add(cloudMed);
        int newIdx = localMedicineList.length - 1;
        if (cloudMed.id.isNotEmpty) localIndexMap["ID_${cloudMed.id}"] = newIdx;
        if (cloudMed.systemId.isNotEmpty) localIndexMap["SYS_${cloudMed.systemId.trim().toUpperCase()}"] = newIdx;
        if (compKey.isNotEmpty) localIndexMap["COMP_$compKey"] = newIdx;
      }
    }
    ProductIntegrityService.deduplicateMedicineList(localMedicineList);
  }
}
