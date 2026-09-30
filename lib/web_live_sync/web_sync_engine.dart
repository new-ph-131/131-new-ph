import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'web_cloud_config.dart';

class WebSyncEngine {
  static Future<Map<String, dynamic>> fetchStoreData({
    required String storeToken,
    required String username,
    required String password,
  }) async {
    try {
      final cleanToken = storeToken.trim().toUpperCase();
      final cleanUser = username.trim().toLowerCase();
      final cleanPass = password.trim();

      // Web Browser uses GET request to guarantee 100% CORS compliance on all browsers
      final uri = Uri.parse(
        "${WebCloudConfig.cloudRelayEndpoint}?action=PULL_STORE_DATA"
        "&storeToken=${Uri.encodeComponent(cleanToken)}"
        "&username=${Uri.encodeComponent(cleanUser)}"
        "&password=${Uri.encodeComponent(cleanPass)}"
      );

      final response = await http.get(uri).timeout(WebCloudConfig.networkTimeout);

      if (response.statusCode == 200 || response.statusCode == 302) {
        final Map<String, dynamic> result = jsonDecode(response.body);
        if (result['status'] == 'SUCCESS') {
          return {
            'success': true,
            'companyName': result['companyName'] ?? 'STORE WORKSTATION',
            'fy': result['fy'] ?? '',
            'profile': result['registryProfile'] ?? {},
            'files': result['files'] ?? {},
            'syncedAt': result['syncedAt'] ?? '',
            'message': 'Connected successfully!',
          };
        } else {
          return {
            'success': false,
            'message': result['message'] ?? 'Invalid Store Key or Password.',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Cloud Relay responded with HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint("WebSyncEngine Error: $e");
      return {
        'success': false,
        'message': 'Connection Error: Please check Store Key & internet.',
      };
    }
  }
}
