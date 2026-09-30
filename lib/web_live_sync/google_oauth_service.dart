import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleOAuthService {
  // Google Official OAuth 2.0 Endpoints
  static const String _oauthAuthUrl = "https://accounts.google.com/o/oauth2/v2/auth";
  static const String _userInfoUrl = "https://www.googleapis.com/oauth2/v3/userinfo";
  static const String _tokenInfoUrl = "https://oauth2.googleapis.com/tokeninfo";

  // Google OAuth 2.0 Web Client Configuration
  static const String clientId = "1072944905499-vm2v2i5dvn0a0d2o4ca36i1vge8cvbn0.apps.googleusercontent.com";
  static const String redirectUri = "https://pharoah-erp.pages.dev";

  // 🔐 1. TRIGGER AUTHENTICATION VIA GOOGLE OFFICIAL POPUP / BROWSER
  static Future<void> startGoogleOAuthFlow() async {
    final String authUrl = "$_oauthAuthUrl"
        "?client_id=$clientId"
        "&redirect_uri=${Uri.encodeComponent(redirectUri)}"
        "&response_type=token%20id_token"
        "&scope=${Uri.encodeComponent('openid email profile https://www.googleapis.com/auth/drive.file')}"
        "&nonce=${DateTime.now().millisecondsSinceEpoch}"
        "&prompt=select_account";

    final Uri uri = Uri.parse(authUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // 🛡️ 2. CRYPTOGRAPHIC TOKEN VERIFICATION & EMAIL EXTRACTION
  static Future<Map<String, dynamic>?> verifyAndSaveToken(String tokenOrCode) async {
    try {
      // Step A: Google ke official token verification endpoint se verify karna
      final verifyUri = Uri.parse("$_userInfoUrl?access_token=$tokenOrCode");
      var response = await http.get(verifyUri);

      if (response.statusCode != 200) {
        // Fallback to id_token verification
        final idTokenUri = Uri.parse("$_tokenInfoUrl?id_token=$tokenOrCode");
        response = await http.get(idTokenUri);
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> userData = jsonDecode(response.body);
        final String verifiedEmail = userData['email'] ?? "";
        final String name = userData['name'] ?? "Google User";
        final bool emailVerified = userData['email_verified'] == true || userData['email_verified'] == "true";

        if (verifiedEmail.isNotEmpty && emailVerified) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('google_account_email', verifiedEmail);
          await prefs.setString('google_account_name', name);
          await prefs.setString('google_auth_token', tokenOrCode);
          await prefs.setBool('is_google_authenticated', true);

          return {
            'email': verifiedEmail,
            'name': name,
            'verified': true
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint("OAuth Verification Error: $e");
      return null;
    }
  }

  // 🚪 3. LOGOUT & DISCONNECT
  static Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('google_account_email');
    await prefs.remove('google_account_name');
    await prefs.remove('google_auth_token');
    await prefs.setBool('is_google_authenticated', false);
  }

  // 🔍 4. GET CURRENT VERIFIED USER
  static Future<String?> getVerifiedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    bool isAuth = prefs.getBool('is_google_authenticated') ?? false;
    if (isAuth) {
      return prefs.getString('google_account_email');
    }
    return null;
  }
}
