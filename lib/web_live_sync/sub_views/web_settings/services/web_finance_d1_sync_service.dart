// FILE: lib/web_live_sync/sub_views/web_settings/services/web_finance_d1_sync_service.dart
// Revision: #PH-REV-797 (ENTERPRISE-FINANCE-D1-SYNC-SERVICE)
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../logic/app_settings_model.dart';
import '../../../../sync_core/d1_sales_ledger_service.dart';
import '../../../../sync_core/modules/settings_sync_module.dart';
import '../../../pharoah_web_manager.dart';
import '../web_settings_sync_coordinator.dart';

/// 💳 WebFinanceD1SyncService
/// Dedicated synchronization service for Payment Gateway, UPI QR Code and Bank Settlement Credentials.
/// Strict File Separation Rule: Fully isolated from Sales, Series Schemes, and Mail setup.
class WebFinanceD1SyncService {
  static const String configDocType = "CONFIG";
  static const String configSyncId = SettingsSyncModule.syncIdConfig;

  static Map<String, String> get _headers => {
    "Content-Type": "application/json",
    "Accept": "application/json",
  };

  /// Centrally saves finance settings, applies optimistic UI update, and dispatches to D1 Edge.
  static Future<bool> saveAndBroadcastFinance({
    required PharoahWebManager webPh,
    required bool showQrCode,
    required String? qrCodePath,
    required String bankAccName,
    required String bankNameBranch,
    required String bankAccNumber,
    required String bankIfsc,
  }) async {
    try {
      final cfg = webPh.appConfig;
      cfg.showQrCode = showQrCode;
      cfg.qrCodePath = qrCodePath;
      cfg.bankAccName = bankAccName.trim().toUpperCase();
      cfg.bankNameBranch = bankNameBranch.trim().toUpperCase();
      cfg.bankAccNumber = bankAccNumber.trim();
      cfg.bankIfsc = bankIfsc.trim().toUpperCase();

      return await WebSettingsSyncCoordinator.saveAndBroadcastConfig(
        webPh: webPh,
        updatedConfig: cfg,
      );
    } catch (e) {
      debugPrint("WebFinanceD1SyncService error: $e");
      return false;
    }
  }
}
