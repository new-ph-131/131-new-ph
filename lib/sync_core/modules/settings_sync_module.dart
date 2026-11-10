// FILE: lib/sync_core/modules/settings_sync_module.dart
// Revision: #PH-REV-794 (ENTERPRISE-SETTINGS-AND-SERIES-SYNC-MODULE)

import 'dart:convert';
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

  /// Applies incoming D1 Edge Ledger APP_CONFIG updates
  static bool applyEdgeEventsToLocalConfig({
    required AppConfig currentConfig,
    required List<Map<String, dynamic>> edgeEvents,
    required void Function(AppConfig) onConfigMutated,
  }) {
    if (edgeEvents.isEmpty) return false;
    AppConfig? updated;
    int bestVer = currentConfig.version;
    int bestTs = currentConfig.updatedAt;

    for (final ev in edgeEvents) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final dynamic rawData = ev["sale_data"];
      if (billId == syncIdConfig && rawData is Map) {
        final evMap = Map<String, dynamic>.from(rawData);
        final String eventFy = (evMap["fy"] ?? ev["fy"] ?? "").toString().trim();
        if (eventFy.isNotEmpty &&
            D1SalesLedgerService.activeFinancialYear.isNotEmpty &&
            eventFy != D1SalesLedgerService.activeFinancialYear) {
          continue;
        }

        final incoming = AppConfig.fromMap(Map<String, dynamic>.from(rawData));
        final bool fieldDiff =
            incoming.developerAllowGstDiaryToUser != currentConfig.developerAllowGstDiaryToUser ||
            incoming.userEnableGstDiary != currentConfig.userEnableGstDiary ||
            incoming.developerAllowBatchHistoryToUser != currentConfig.developerAllowBatchHistoryToUser ||
            incoming.userEnableBatchHistory != currentConfig.userEnableBatchHistory ||
            incoming.showLogo != currentConfig.showLogo ||
            incoming.logoPath != currentConfig.logoPath ||
            incoming.printFormat != currentConfig.printFormat ||
            incoming.showTerms != currentConfig.showTerms ||
            incoming.termsAndConditions != currentConfig.termsAndConditions ||
            incoming.showStaffSign != currentConfig.showStaffSign ||
            incoming.signLabel != currentConfig.signLabel ||
            incoming.showCustomerSignChallan != currentConfig.showCustomerSignChallan ||
            incoming.showQrCode != currentConfig.showQrCode ||
            incoming.qrCodePath != currentConfig.qrCodePath ||
            incoming.bankAccName != currentConfig.bankAccName ||
            incoming.bankAccNumber != currentConfig.bankAccNumber ||
            incoming.bankIfsc != currentConfig.bankIfsc ||
            incoming.bankNameBranch != currentConfig.bankNameBranch ||
            incoming.isMailActive != currentConfig.isMailActive ||
            incoming.smtpMailID != currentConfig.smtpMailID ||
            incoming.smtpMailPass != currentConfig.smtpMailPass ||
            incoming.smtpHost != currentConfig.smtpHost ||
            incoming.smtpPort != currentConfig.smtpPort ||
            incoming.caName != currentConfig.caName ||
            incoming.caMailID != currentConfig.caMailID ||
            incoming.caPhone != currentConfig.caPhone ||
            incoming.isAuditMode != currentConfig.isAuditMode ||
            incoming.salePrefix != currentConfig.salePrefix ||
            incoming.purPrefix != currentConfig.purPrefix ||
            incoming.saleChallanPrefix != currentConfig.saleChallanPrefix ||
            incoming.saleReturnPrefix != currentConfig.saleReturnPrefix ||
            incoming.purReturnPrefix != currentConfig.purReturnPrefix;

        if (incoming.version > bestVer ||
            incoming.updatedAt > bestTs ||
            (bestTs == 0 && fieldDiff)) {
          updated = incoming;
          bestVer = incoming.version;
          bestTs = incoming.updatedAt;
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
