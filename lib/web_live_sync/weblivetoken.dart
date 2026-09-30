import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class WebLiveToken {
  static const String _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// 1. Generate a collision-proof, secure Store Live Key (PH-LIVE-XXXX-XXXX)
  static String generateSecureToken() {
    final random = Random.secure();
    String part1 = List.generate(4, (_) => _chars[random.nextInt(_chars.length)]).join();
    String part2 = List.generate(4, (_) => _chars[random.nextInt(_chars.length)]).join();
    return 'PH-LIVE-$part1-$part2';
  }

  /// 2. Fetch existing token or generate a permanent new one for this company ID
  static Future<String> getOrCreateToken(String companyId) async {
    if (companyId.isEmpty) return '';
    final prefs = await SharedPreferences.getInstance();
    final key = 'web_live_token_$companyId';
    String? existingToken = prefs.getString(key);

    if (existingToken != null && existingToken.trim().isNotEmpty) {
      return existingToken.trim().toUpperCase();
    }

    String newToken = generateSecureToken();
    await prefs.setString(key, newToken);
    return newToken;
  }

  /// 3. Get token if already generated
  static Future<String?> getToken(String companyId) async {
    if (companyId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('web_live_token_$companyId');
  }

  /// 4. Force regenerate token (if store owner wants to revoke web access)
  static Future<String> regenerateToken(String companyId) async {
    if (companyId.isEmpty) return '';
    final prefs = await SharedPreferences.getInstance();
    final key = 'web_live_token_$companyId';
    String newToken = generateSecureToken();
    await prefs.setString(key, newToken);
    return newToken;
  }

  /// 5. Token format validator
  static bool isValidTokenFormat(String token) {
    final clean = token.trim().toUpperCase();
    return RegExp(r'^PH-LIVE-[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(clean);
  }
}
