// FILE: lib/sync_core/modules/settings_sync_module.dart
// Revision: #PH-REV-820 (CAUSAL-HWM-SETTINGS-SYNC-MODULE)

import 'package:flutter/foundation.dart';
import '../../models.dart';
import '../../logic/app_settings_model.dart';
import '../d1_sales_ledger_service.dart';
import '../outbox/sync_queue_manager.dart';

/// SettingsSyncModule: Dedicated Synchronization & Delta Engine for AppConfig & NumberingSeries.
/// Strict File Separation Rule: Decoupled from Sales, Purchases, Challans, and GST Diary.
class SettingsSyncModule {
  static const String documentTypeConfig = "CONFIG";
  static const String documentTypeSeries = "SERIES";
  static const String syncIdConfig = "APP_CONFIG_MASTER";
  static const String syncIdSeries = "NUMBERING_SERIES_MASTER";

  /// Enqueues AppConfig update to the local Outbox mutation queue
  static void onConfigSaved(AppConfig config, String storeToken, {String fy = ""}) {
    if (storeToken.trim().isEmpty) return;
    config.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final map = config.toMap();
    if (fy.isNotEmpty) {
      map["fy"] = fy;
    }

    SyncQueueManager.enqueueMutation(
      syncId: syncIdConfig,
      storeToken: storeToken.trim().toUpperCase(),
      docType: documentTypeConfig,
      currentVersion: config.version,
      isDelete: false,
      rawPayload: map,
    );
  }

  /// Enqueues NumberingSeries updates to the local Outbox mutation queue
  static void onSeriesSaved(List<NumberingSeries> seriesList, String storeToken, {String fy = ""}) {
    if (storeToken.trim().isEmpty) return;
    final payloadList = seriesList.map((e) => e.toMap()).toList();
    final map = <String, dynamic>{
      "series": payloadList,
      "updatedAt": DateTime.now().millisecondsSinceEpoch,
    };
    if (fy.isNotEmpty) {
      map["fy"] = fy;
    }

    SyncQueueManager.enqueueMutation(
      syncId: syncIdSeries,
      storeToken: storeToken.trim().toUpperCase(),
      docType: documentTypeSeries,
      currentVersion: DateTime.now().millisecondsSinceEpoch,
      isDelete: false,
      rawPayload: map,
    );
  }

  static bool _hwmMapsEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  static bool _metaMapsEqual(Map<String, ChallanHwmState> a, Map<String, ChallanHwmState> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null) return false;
      if (other.value != e.value.value ||
          other.gen != e.value.gen ||
          other.seq != e.value.seq ||
          other.op != e.value.op) {
        return false;
      }
    }
    return true;
  }

  /// Applies incoming D1 Edge Ledger APP_CONFIG updates with causal HWM + rollback resolution
  static bool applyEdgeEventsToLocalConfig({
    required AppConfig currentConfig,
    required List<Map<String, dynamic>> edgeEvents,
    required void Function(AppConfig) onConfigMutated,
    Map<String, int> recordFloor = const {},
  }) {
    if (edgeEvents.isEmpty) return false;
    AppConfig? updated;
    AppConfig workingConfig = currentConfig;
    int bestVer = currentConfig.version;
    int bestTs = currentConfig.updatedAt;

    for (final ev in edgeEvents) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final int evSeq = int.tryParse(ev["seq"]?.toString() ?? "0") ?? 0;
      final dynamic rawData = ev["sale_data"];
      if (billId == syncIdConfig && rawData is Map) {
        final evMap = Map<String, dynamic>.from(rawData);
        final String eventFy = (evMap["fy"] ?? ev["fy"] ?? "").toString().trim();
        if (eventFy.isNotEmpty &&
            D1SalesLedgerService.activeFinancialYear.isNotEmpty &&
            eventFy != D1SalesLedgerService.activeFinancialYear) {
          continue;
        }

        final incoming = AppConfig.fromMap(evMap);
        if (evSeq > 0) {
          incoming.challanHwmMeta.forEach((_, st) {
            if (st.seq == 0) st.seq = evSeq;
          });
        }
        final bool fieldDiff =
            incoming.developerAllowGstDiaryToUser != workingConfig.developerAllowGstDiaryToUser ||
            incoming.userEnableGstDiary != workingConfig.userEnableGstDiary ||
            incoming.developerAllowBatchHistoryToUser != workingConfig.developerAllowBatchHistoryToUser ||
            incoming.userEnableBatchHistory != workingConfig.userEnableBatchHistory ||
            incoming.showLogo != workingConfig.showLogo ||
            incoming.logoPath != workingConfig.logoPath ||
            incoming.printFormat != workingConfig.printFormat ||
            incoming.showTerms != workingConfig.showTerms ||
            incoming.termsAndConditions != workingConfig.termsAndConditions ||
            incoming.showStaffSign != workingConfig.showStaffSign ||
            incoming.signLabel != workingConfig.signLabel ||
            incoming.showCustomerSignChallan != workingConfig.showCustomerSignChallan ||
            incoming.showQrCode != workingConfig.showQrCode ||
            incoming.qrCodePath != workingConfig.qrCodePath ||
            incoming.bankAccName != workingConfig.bankAccName ||
            incoming.bankAccNumber != workingConfig.bankAccNumber ||
            incoming.bankIfsc != workingConfig.bankIfsc ||
            incoming.bankNameBranch != workingConfig.bankNameBranch ||
            incoming.isMailActive != workingConfig.isMailActive ||
            incoming.smtpMailID != workingConfig.smtpMailID ||
            incoming.smtpMailPass != workingConfig.smtpMailPass ||
            incoming.smtpHost != workingConfig.smtpHost ||
            incoming.smtpPort != workingConfig.smtpPort ||
            incoming.caName != workingConfig.caName ||
            incoming.caMailID != workingConfig.caMailID ||
            incoming.caPhone != workingConfig.caPhone ||
            incoming.isAuditMode != workingConfig.isAuditMode ||
            incoming.salePrefix != workingConfig.salePrefix ||
            incoming.purPrefix != workingConfig.purPrefix ||
            incoming.saleChallanPrefix != workingConfig.saleChallanPrefix ||
            incoming.saleReturnPrefix != workingConfig.saleReturnPrefix ||
            incoming.purReturnPrefix != workingConfig.purReturnPrefix;

        final merged = AppConfig.mergeHwmMapsWithMeta(
          localHwm: workingConfig.challanHwm,
          localMeta: workingConfig.challanHwmMeta,
          remoteHwm: incoming.challanHwm,
          remoteMeta: incoming.challanHwmMeta,
          recordFloor: recordFloor,
        );
        final bool hwmChanged = !_hwmMapsEqual(merged.hwm, workingConfig.challanHwm) ||
            !_metaMapsEqual(merged.meta, workingConfig.challanHwmMeta);
        if (hwmChanged) {
          workingConfig.challanHwm = merged.hwm;
          workingConfig.challanHwmMeta = merged.meta;
        }
        if (incoming.challanHwmTailMigrated) {
          workingConfig.challanHwmTailMigrated = true;
        }
        final bool settingsNewer = incoming.version > bestVer ||
            incoming.updatedAt > bestTs ||
            (bestTs == 0 && fieldDiff);
        if (settingsNewer) {
          updated = incoming;
          updated.challanHwm = merged.hwm;
          updated.challanHwmMeta = merged.meta;
          updated.challanHwmTailMigrated =
              workingConfig.challanHwmTailMigrated || incoming.challanHwmTailMigrated;
          workingConfig = updated;
          bestVer = incoming.version;
          bestTs = incoming.updatedAt;
        } else if (hwmChanged ||
            (incoming.challanHwmTailMigrated && !workingConfig.challanHwmTailMigrated)) {
          workingConfig.challanHwm = merged.hwm;
          workingConfig.challanHwmMeta = merged.meta;
          workingConfig.challanHwmTailMigrated =
              workingConfig.challanHwmTailMigrated || incoming.challanHwmTailMigrated;
          updated = workingConfig;
        }
      }
    }

    if (updated != null) {
      onConfigMutated(updated);
      return true;
    }
    return false;
  }

  /// Applies incoming D1 Edge Ledger NUMBERING_SERIES updates
  static bool applyEdgeEventsToLocalSeries({
    required List<NumberingSeries> currentSeries,
    required List<Map<String, dynamic>> edgeEvents,
    required void Function(List<NumberingSeries>) onSeriesMutated,
  }) {
    if (edgeEvents.isEmpty) return false;
    List<NumberingSeries>? updatedList;

    for (final ev in edgeEvents) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final dynamic rawData = ev["sale_data"];
      if (billId == syncIdSeries && rawData is Map) {
        final evMap = Map<String, dynamic>.from(rawData);
        final String eventFy = (evMap["fy"] ?? ev["fy"] ?? "").toString().trim();
        if (eventFy.isNotEmpty &&
            D1SalesLedgerService.activeFinancialYear.isNotEmpty &&
            eventFy != D1SalesLedgerService.activeFinancialYear) {
          continue;
        }

        final dynamic seriesRaw = evMap["series"];
        if (seriesRaw is List) {
          final incomingList = seriesRaw
              .map((e) => NumberingSeries.fromMap(Map<String, dynamic>.from(e)))
              .toList();
          if (incomingList.isNotEmpty) {
            updatedList = incomingList;
          }
        }
      }
    }

    if (updatedList != null) {
      onSeriesMutated(updatedList);
      return true;
    }
    return false;
  }
}
