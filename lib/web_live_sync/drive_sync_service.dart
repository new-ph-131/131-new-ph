import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../pharoah_manager.dart';

class DriveSyncService {
  static const String defaultEndpoint = "https://script.google.com/macros/s/AKfycbyKFFt9WK-xB1qLRTD7M-b4jSlpCBoBfJ18x8FUP1wFBzbQ-dQgyjm1qPfvl2kQmaSl/exec";

  static Future<bool> pushDataToCloud(PharoahManager ph) async {
    try {
      if (ph.activeCompany == null || ph.currentFY.isEmpty) return false;

      final workingDir = await ph.getWorkingPath();
      if (workingDir.isEmpty) return false;

      List<String> fileNames = [
        'meds.json', 'parts.json', 'sales.json', 'purc.json',
        'bats.json', 'vouc.json', 's_challan.json', 'p_challan.json',
        's_return.json', 'p_return.json', 'banks.json', 'config.json',
        'series.json', 'shortage.json', 'routs.json', 'comps.json'
      ];

      Map<String, String> filesPayload = {};
      for (var name in fileNames) {
        final f = File('$workingDir/$name');
        if (await f.exists()) {
          filesPayload[name] = await f.readAsString();
        }
      }

      final payload = {
        "action": "PUSH_DATA",
        "companyId": ph.activeCompany!.id,
        "fy": ph.currentFY,
        "registryProfile": ph.activeCompany!.toMap(),
        "files": filesPayload,
      };

      final response = await http.post(
        Uri.parse(defaultEndpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_cloud_sync_time', DateTime.now().toIso8601String());
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Drive Sync Push Error: $e");
      return false;
    }
  }

  static Future<String> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    String? timeStr = prefs.getString('last_cloud_sync_time');
    if (timeStr == null) return "Never";
    try {
      DateTime dt = DateTime.parse(timeStr);
      return "${dt.day}/${dt.month}/${dt.year} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return "Never";
    }
  }
}
