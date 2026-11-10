// FILE: lib/web_live_sync/sub_views/web_settings/services/web_settings_d1_sync_service.dart
// Revision: #PH-REV-794 (ENTERPRISE-WEB-SETTINGS-D1-SYNC-SERVICE)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../models.dart';
import '../../../../logic/app_settings_model.dart';
import '../../../../sync_core/d1_sales_ledger_service.dart';
import '../../../../sync_core/modules/settings_sync_module.dart';

/// 🌐 WebSettingsD1SyncService
/// Dedicated synchronization service for AppConfig, Branding, Signatures, Series Schemes & Finance.
/// Connects Web and Mobile App directly through Cloudflare D1 Edge Ledger in ~200 milliseconds.
/// Strict File Separation Rule: Isolated from Sales, Purchases, Challans, and GST Diary.
class WebSettingsD1SyncService {
  static const String configDocType = "CONFIG";
  static const String seriesDocType = "SERIES";
  static const String configSyncId = SettingsSyncModule.syncIdConfig;
  static const String seriesSyncId = SettingsSyncModule.syncIdSeries;

  static Map<String, String> get _headers => {
    "Content-Type": "application/json",
    "Accept": "application/json",
  };

  /// Dispatches AppConfig directly to Cloudflare D1 Edge with fast ~200ms confirmation.
  static Future<bool> syncConfigToD1({
    required AppConfig config,
    required String storeToken,
    required String financialYear,
    String clientSource = "WEB_PORTAL",
  }) async {
    if (!D1SalesLedgerService.USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) {
      return true;
    }

    final cfgMap = config.toMap();
    cfgMap["doc_type"] = configDocType;
    cfgMap["id"] = configSyncId;
    if (financialYear.trim().isNotEmpty) {
      cfgMap["fy"] = financialYear.trim();
    } else if (D1SalesLedgerService.activeFinancialYear.isNotEmpty) {
      cfgMap["fy"] = D1SalesLedgerService.activeFinancialYear;
    }

    final payload = {
      "storeToken": storeToken.trim().toUpperCase(),
      "source": clientSource,
      "action": "CONFIG_UPDATED",
      "entityId": configSyncId,
      "unmarkedIds": [configSyncId],
      "sale_event": {
        "id": configSyncId,
        "bill_no": "APP_CONFIG",
        "version": config.version,
        "action": "UPDATE",
        "status": "Active",
        "client_source": clientSource,
        "payload": cfgMap,
      },
    };

    try {
      final response = await http
          .post(
            Uri.parse(D1SalesLedgerService.endpoint),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));

      final bool success = response.statusCode == 200 || response.body.contains("SUCCESS");
      if (kDebugMode) {
        print("⚡ [WebSettingsD1SyncService] Config Synced to D1: $success (${response.statusCode})");
      }
      return success;
    } catch (e) {
      if (kDebugMode) {
        print("⚠️ [WebSettingsD1SyncService] D1 Config Sync Error: $e");
      }
      return false;
    }
  }

  /// Dispatches NumberingSeries directly to Cloudflare D1 Edge with fast ~200ms confirmation.
  static Future<bool> syncSeriesToD1({
    required List<NumberingSeries> seriesList,
    required String storeToken,
    required String financialYear,
    String clientSource = "WEB_PORTAL",
  }) async {
    if (!D1SalesLedgerService.USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) {
      return true;
    }

    final seriesPayload = {
      "doc_type": seriesDocType,
      "id": seriesSyncId,
      "fy": financialYear.trim().isNotEmpty ? financialYear.trim() : D1SalesLedgerService.activeFinancialYear,
      "series": seriesList.map((e) => e.toMap()).toList(),
      "updatedAt": DateTime.now().millisecondsSinceEpoch,
    };

    final payload = {
      "storeToken": storeToken.trim().toUpperCase(),
      "source": clientSource,
      "action": "SERIES_UPDATED",
      "entityId": seriesSyncId,
      "unmarkedIds": [seriesSyncId],
      "sale_event": {
        "id": seriesSyncId,
        "bill_no": "NUMBERING_SERIES",
        "version": DateTime.now().millisecondsSinceEpoch,
        "action": "UPDATE",
        "status": "Active",
        "client_source": clientSource,
        "payload": seriesPayload,
      },
    };

    try {
      final response = await http
          .post(
            Uri.parse(D1SalesLedgerService.endpoint),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));

      return response.statusCode == 200 || response.body.contains("SUCCESS");
    } catch (e) {
      if (kDebugMode) {
        print("⚠️ [WebSettingsD1SyncService] D1 Series Sync Error: $e");
      }
      return false;
    }
  }
}
