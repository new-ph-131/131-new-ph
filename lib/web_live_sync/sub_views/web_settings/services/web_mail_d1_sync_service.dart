// FILE: lib/web_live_sync/sub_views/web_settings/services/web_mail_d1_sync_service.dart
// Revision: #PH-REV-797 (ENTERPRISE-MAIL-D1-SYNC-SERVICE)
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../logic/app_settings_model.dart';
import '../../../../sync_core/d1_sales_ledger_service.dart';
import '../../../../sync_core/modules/settings_sync_module.dart';
import '../../../pharoah_web_manager.dart';
import '../web_settings_sync_coordinator.dart';

/// 📧 WebMailD1SyncService
/// Dedicated synchronization service for SMTP Mail & Automated SMS / Dispatch Protocols.
/// Strict File Separation Rule: Fully isolated from Sales, Series Schemes, and Finance setup.
class WebMailD1SyncService {
  static const String configDocType = "CONFIG";
  static const String configSyncId = SettingsSyncModule.syncIdConfig;

  /// Sanitizes email string (removes accidental interior/leading/trailing spaces)
  static String cleanEmail(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
  }

  /// Centrally saves SMTP mail settings, applies optimistic UI update, and dispatches to D1 Edge.
  static Future<bool> saveAndBroadcastMail({
    required PharoahWebManager webPh,
    required bool isMailActive,
    required String smtpMailID,
    required String smtpMailPass,
    required String smtpHost,
    required int smtpPort,
  }) async {
    try {
      final cfg = webPh.appConfig;
      cfg.isMailActive = isMailActive;
      cfg.smtpMailID = cleanEmail(smtpMailID);
      cfg.smtpMailPass = smtpMailPass.trim();
      cfg.smtpHost = smtpHost.trim().isNotEmpty ? smtpHost.trim() : "smtp.gmail.com";
      cfg.smtpPort = smtpPort > 0 ? smtpPort : 587;

      return await WebSettingsSyncCoordinator.saveAndBroadcastConfig(
        webPh: webPh,
        updatedConfig: cfg,
      );
    } catch (e) {
      debugPrint("WebMailD1SyncService error: $e");
      return false;
    }
  }
}
