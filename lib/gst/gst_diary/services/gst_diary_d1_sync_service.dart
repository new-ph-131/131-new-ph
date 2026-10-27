// FILE: lib/gst/gst_diary/services/gst_diary_d1_sync_service.dart
// Revision: #PH-REV-785 (ENTERPRISE-GST-DIARY-D1-EDGE-SYNC-SERVICE)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../logic/app_settings_model.dart';
import '../../../sync_core/d1_sales_ledger_service.dart';
import '../../../sync_core/modules/gst_diary_sync_module.dart';
import '../gst_diary_models.dart';

/// 🌐 GstDiaryD1SyncService
/// Dedicated real-time synchronization service for GST Diary Settlement Sessions & GST Diary Access Permissions.
/// Bridges Web and Mobile App through Cloudflare D1 (sale_events Edge Ledger + erp_master_sync Outbox).
/// Strict File Separation Rule: Isolated from Sales, Purchases, Vouchers, and Challans.
class GstDiaryD1SyncService {
  static const String docType = "GST_DIARY_SESSION";
  static const String configDocType = "APP_CONFIG";
  static const String configSyncId = "APP_CONFIG_MASTER";

  static Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Accept": "application/json",
      };

  /// 📤 1. Dispatches a created or modified GST Diary Session to Cloudflare D1 Edge Bus + Outbox
  static void onSessionSaved(
    GstDiarySession session,
    String storeToken, {
    String clientSource = "WEB_PORTAL",
  }) {
    if (storeToken.trim().isEmpty) return;

    session.isDeleted = 0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (session.updatedAt <= 0 || session.updatedAt < now) {
      session.updatedAt = now;
    }

    // 1. Unmark any previous tombstones in D1 so it is never suppressed
    D1SalesLedgerService.unmarkPermanentlyDeleted(session.id, session.title);

    // 2. Record monotonic known version
    final int knownVer = D1SalesLedgerService.getKnownVersion(session.id, session.title);
    if (knownVer >= session.version) {
      session.version = knownVer + 1;
    }
    D1SalesLedgerService.recordKnownVersion(session.id, session.title, session.version);

    // 3. Enqueue mutation via GstDiarySyncModule into outbox buffer
    GstDiarySyncModule.onSessionSaved(session, storeToken, isDelete: false);

    // 4. Push instant D1 Edge Ledger mutation (<30ms)
    _pushSessionEdgeEvent(
      session: session,
      storeToken: storeToken,
      action: "UPDATE",
      clientSource: clientSource,
    );
    debugPrint("⚡ [GstDiaryD1Sync] Session '${session.title}' (${session.id}) v${session.version} queued & pushed to D1 Edge");
  }

  /// 🗑️ 2. Dispatches a permanent GST Diary Session delete to Cloudflare D1 Edge Bus + Outbox
  static void onSessionDeleted(
    String sessionId,
    String storeToken, {
    String sessionTitle = "",
    String clientSource = "WEB_PORTAL",
  }) {
    if (storeToken.trim().isEmpty || sessionId.trim().isEmpty) return;

    final cleanId = sessionId.trim();
    D1SalesLedgerService.markPermanentlyDeleted(cleanId, sessionTitle);
    D1SalesLedgerService.recordKnownVersion(cleanId, sessionTitle, 999999);

    final dummyDeleted = GstDiarySession(
      id: cleanId,
      title: sessionTitle.isNotEmpty ? sessionTitle : "Deleted Session",
      createdAt: DateTime.now().millisecondsSinceEpoch,
      fromDate: "",
      toDate: "",
      totalPurchaseItc: 0,
      totalSaleOutputGst: 0,
      netGstPayable: 0,
      deductedAmount: 0,
      status: "Deleted",
      version: 999999,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      isDeleted: 1,
    );
    GstDiarySyncModule.onSessionSaved(dummyDeleted, storeToken, isDelete: true);

    _pushSessionDeleteEdgeEvent(
      sessionId: cleanId,
      sessionTitle: sessionTitle,
      storeToken: storeToken,
      clientSource: clientSource,
    );
    debugPrint("🗑️ [GstDiaryD1Sync] Session $cleanId marked deleted and pushed to D1 Edge");
  }

  /// 🔐 3. Dispatches User Control / GST Diary Permission changes via D1 Edge Ledger (<30ms)
  static void onAppConfigSaved(
    AppConfig config,
    String storeToken, {
    String clientSource = "WEB_PORTAL",
  }) {
    if (!D1SalesLedgerService.USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return;
    final cfgMap = config.toMap();
    cfgMap["doc_type"] = configDocType;
    cfgMap["id"] = configSyncId;

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
    http
        .post(
          Uri.parse(D1SalesLedgerService.endpoint),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 6))
        .catchError((_) => http.Response("", 500));
  }

  static Future<bool> _pushSessionEdgeEvent({
    required GstDiarySession session,
    required String storeToken,
    required String action,
    required String clientSource,
  }) async {
    if (!D1SalesLedgerService.USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    try {
      final sMap = session.toMap();
      sMap["doc_type"] = docType;
      if (D1SalesLedgerService.activeFinancialYear.isNotEmpty) {
        sMap["fy"] = D1SalesLedgerService.activeFinancialYear;
      }
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "GST_SESSION_SAVED",
        "entityId": session.id,
        "unmarkedIds": [session.id],
        "sale_event": {
          "id": session.id,
          "bill_no": session.title,
          "version": session.version,
          "action": action,
          "status": session.status,
          "client_source": clientSource,
          "payload": sMap,
        },
      };
      final res = await http
          .post(
            Uri.parse(D1SalesLedgerService.endpoint),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint("⚠ [GstDiaryD1Sync] Edge push notice: $e");
      return false;
    }
  }

  static Future<bool> _pushSessionDeleteEdgeEvent({
    required String sessionId,
    required String sessionTitle,
    required String storeToken,
    required String clientSource,
  }) async {
    if (!D1SalesLedgerService.USE_D1_EDGE_LEDGER || storeToken.trim().isEmpty) return false;
    try {
      final payload = {
        "storeToken": storeToken.trim().toUpperCase(),
        "source": clientSource,
        "action": "DELETE_GST_SESSION",
        "entityId": sessionId,
        "deletedIds": [sessionId],
        "sale_event": {
          "id": sessionId,
          "bill_no": sessionTitle,
          "version": 999999,
          "action": "DELETE",
          "status": "Deleted",
          "client_source": clientSource,
          "payload": {
            "doc_type": docType,
            "id": sessionId,
            "title": sessionTitle,
            "is_deleted": 1,
            "isDeleted": 1,
            "status": "Deleted",
          },
        },
      };
      final res = await http
          .post(
            Uri.parse(D1SalesLedgerService.endpoint),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint("⚠ [GstDiaryD1Sync] Edge delete notice: $e");
      return false;
    }
  }

  /// 📥 4. Merges incoming D1 Edge Ledger events (from fetchSaleDeltas) into local GST Diary Sessions list
  static bool applyEdgeEventsToLocalSessions(
    List<GstDiarySession> localSessions,
    List<Map<String, dynamic>> events,
  ) {
    if (events.isEmpty) return false;
    bool mutated = false;

    for (final ev in events) {
      final String billId = (ev["bill_id"] ?? "").toString().trim();
      final String action = (ev["action"] ?? "INSERT").toString().toUpperCase();
      final int version = int.tryParse(ev["version"]?.toString() ?? "1") ?? 1;
      final dynamic rawData = ev["sale_data"];

      final bool isGstSessionPayload = rawData is Map &&
          (rawData["doc_type"] == docType ||
              rawData.containsKey("includedBillIds") ||
              rawData.containsKey("deductedAmount") ||
              billId.startsWith("SESS_"));

      if (action == "DELETE") {
        final bool matchesLocal = localSessions.any(
          (s) => billId.isNotEmpty && s.id.trim().toUpperCase() == billId.toUpperCase(),
        );
        if (isGstSessionPayload || matchesLocal) {
          D1SalesLedgerService.markPermanentlyDeleted(billId);
          D1SalesLedgerService.recordKnownVersion(billId, "", 999999);
          final int beforeLen = localSessions.length;
          localSessions.removeWhere(
            (s) => billId.isNotEmpty && s.id.trim().toUpperCase() == billId.toUpperCase(),
          );
          if (localSessions.length != beforeLen) {
            mutated = true;
          }
        }
      } else if (isGstSessionPayload && rawData is Map) {
        final mapData = Map<String, dynamic>.from(rawData);
        final incoming = GstDiarySession.fromMap(mapData);
        if (billId.isNotEmpty) incoming.id = billId;
        incoming.version = version;
        final DateTime? sessDate = DateTime.tryParse(incoming.fromDate);
        if (!D1SalesLedgerService.doesEventBelongToActiveFY(mapData, sessDate)) {
          continue;
        }

        if (incoming.isDeleted == 1 || incoming.status == "Deleted") {
          D1SalesLedgerService.markPermanentlyDeleted(incoming.id);
          final int beforeLen = localSessions.length;
          localSessions.removeWhere(
            (s) => s.id.trim().toUpperCase() == incoming.id.trim().toUpperCase(),
          );
          if (localSessions.length != beforeLen) mutated = true;
          continue;
        }

        if (D1SalesLedgerService.isBillDeleted(incoming.id)) {
          if (version > 1) {
            D1SalesLedgerService.unmarkPermanentlyDeleted(incoming.id);
          } else {
            continue;
          }
        }

        D1SalesLedgerService.recordKnownVersion(incoming.id, incoming.title, version);
        final int idx = localSessions.indexWhere(
          (s) => s.id.trim().toUpperCase() == incoming.id.trim().toUpperCase(),
        );
        if (idx != -1) {
          final existing = localSessions[idx];
          if (version > existing.version ||
              (version == existing.version && incoming.updatedAt > existing.updatedAt) ||
              existing.status != incoming.status ||
              existing.title != incoming.title ||
              existing.remarks != incoming.remarks) {
            localSessions[idx] = incoming;
            mutated = true;
          }
        } else {
          localSessions.insert(0, incoming);
          mutated = true;
        }
      }
    }

    if (mutated) {
      localSessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return mutated;
  }

  /// 📥 5. Applies incoming D1 Edge Ledger APP_CONFIG updates (e.g., User Control GST Diary permissions)
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
      if (billId == configSyncId && rawData is Map) {
        final incoming = AppConfig.fromMap(Map<String, dynamic>.from(rawData));
        final bool fieldDiff =
            incoming.developerAllowGstDiaryToUser != currentConfig.developerAllowGstDiaryToUser ||
            incoming.userEnableGstDiary != currentConfig.userEnableGstDiary ||
            incoming.developerAllowBatchHistoryToUser != currentConfig.developerAllowBatchHistoryToUser ||
            incoming.userEnableBatchHistory != currentConfig.userEnableBatchHistory;
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
}
