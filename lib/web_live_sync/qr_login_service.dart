// FILE: lib/web_live_sync/qr_login_service.dart
import "dart:convert";
import "dart:math";
import "dart:typed_data";

import "package:crypto/crypto.dart";
import "package:http/http.dart" as http;

import "web_cloud_config.dart";

enum QrPollStatus { pending, approved, expired, error }

class QrSessionChallenge {
  final String sid;
  final String otp;
  final String qrPayload;
  final int expiresAtMs;

  const QrSessionChallenge({
    required this.sid,
    required this.otp,
    required this.qrPayload,
    required this.expiresAtMs,
  });
}

class QrScannedTarget {
  final String sid;
  final String otp;

  const QrScannedTarget({required this.sid, required this.otp});
}

class QrLoginCredentials {
  final String storeToken;
  final String username;
  final String password;
  final String companyName;

  const QrLoginCredentials({
    required this.storeToken,
    required this.username,
    required this.password,
    this.companyName = "",
  });
}

class QrPollResult {
  final QrPollStatus status;
  final QrLoginCredentials? credentials;
  final String errorMessage;

  const QrPollResult({
    required this.status,
    this.credentials,
    this.errorMessage = "",
  });
}

class QrApproveResult {
  final bool success;
  final bool expired;
  final String message;

  const QrApproveResult({
    required this.success,
    this.expired = false,
    this.message = "",
  });
}

class QrLoginService {
  static const String payloadPrefix = "PHAROAH_QR_V1";
  static const int sessionTtlSeconds = 120;
  static String get endpoint => "${WebCloudConfig.webPortalUrl}/api/qr_login";

  static final Random _secureRandom = Random.secure();

  static String _randomUrlSafe(int byteCount) {
    final bytes = List<int>.generate(byteCount, (_) => _secureRandom.nextInt(256));
    return base64UrlEncode(bytes).replaceAll("=", "");
  }

  static QrSessionChallenge createLocalChallenge() {
    final sid = "QR_${_randomUrlSafe(18)}";
    final otp = _randomUrlSafe(32);
    final payload = "$payloadPrefix|$sid|$otp";
    final expiresAtMs =
        DateTime.now().millisecondsSinceEpoch + (sessionTtlSeconds * 1000);
    return QrSessionChallenge(
      sid: sid,
      otp: otp,
      qrPayload: payload,
      expiresAtMs: expiresAtMs,
    );
  }

  static QrScannedTarget? parseQrPayload(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim();
    if (clean.isEmpty) return null;
    final parts = clean.split("|");
    if (parts.length != 3) return null;
    if (parts[0].trim() != payloadPrefix) return null;
    final sid = parts[1].trim();
    final otp = parts[2].trim();
    if (!RegExp(r"^[A-Za-z0-9_-]{16,80}$").hasMatch(sid)) return null;
    try {
      final decodedOtp = _decodeBase64Url(otp);
      if (decodedOtp.length != 32) return null;
    } catch (_) {
      return null;
    }
    return QrScannedTarget(sid: sid, otp: otp);
  }

  static List<int> _decodeBase64Url(String input) {
    var normalized = input.trim();
    final rem = normalized.length % 4;
    if (rem > 0) {
      normalized = normalized.padRight(normalized.length + (4 - rem), "=");
    }
    return base64Url.decode(normalized);
  }

  static Uint8List _deriveKeystream(
    List<int> otpBytes,
    List<int> nonce,
    int length,
  ) {
    final out = Uint8List(length);
    var offset = 0;
    var counter = 0;
    while (offset < length) {
      final blockInput = <int>[
        ...otpBytes,
        ...nonce,
        (counter >> 24) & 0xFF,
        (counter >> 16) & 0xFF,
        (counter >> 8) & 0xFF,
        counter & 0xFF,
      ];
      final digest = sha256.convert(blockInput).bytes;
      final copyLen = min(digest.length, length - offset);
      out.setRange(offset, offset + copyLen, digest);
      offset += copyLen;
      counter++;
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Encrypts payload JSON with the QR-embedded ephemeral OTP key (nonce + CTR + HMAC-SHA256).
  static String sealPayload(Map<String, dynamic> data, String otpB64) {
    final otpBytes = _decodeBase64Url(otpB64);
    if (otpBytes.length != 32) {
      throw ArgumentError("Invalid QR OTP key length");
    }
    final nonce = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    final plain = utf8.encode(jsonEncode(data));
    final stream = _deriveKeystream(otpBytes, nonce, plain.length);
    final cipher = List<int>.generate(plain.length, (i) => plain[i] ^ stream[i]);
    final mac = Hmac(sha256, otpBytes).convert(<int>[...nonce, ...cipher]).bytes;
    return base64UrlEncode(<int>[...nonce, ...cipher, ...mac]).replaceAll("=", "");
  }

  /// Decrypts and authenticates sealed payload using the local OTP key. Returns null if tampered.
  static Map<String, dynamic>? unsealPayload(String sealedB64, String otpB64) {
    try {
      final otpBytes = _decodeBase64Url(otpB64);
      if (otpBytes.length != 32) return null;
      final raw = _decodeBase64Url(sealedB64);
      // 16-byte nonce + >=1 byte cipher + 32-byte HMAC
      if (raw.length < 49) return null;
      final nonce = raw.sublist(0, 16);
      final cipher = raw.sublist(16, raw.length - 32);
      final tag = raw.sublist(raw.length - 32);

      final expectedTag =
          Hmac(sha256, otpBytes).convert(<int>[...nonce, ...cipher]).bytes;
      if (!_constantTimeEquals(tag, expectedTag)) {
        return null;
      }

      final stream = _deriveKeystream(otpBytes, nonce, cipher.length);
      final plain = List<int>.generate(cipher.length, (i) => cipher[i] ^ stream[i]);
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> initSession(
    String sid, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final res = await httpClient
          .post(
            Uri.parse(endpoint),
            headers: const {"Content-Type": "application/json"},
            body: jsonEncode({"action": "INIT", "sid": sid}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data is Map && data["status"] == "SUCCESS";
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (shouldClose) httpClient.close();
    }
  }

  static Future<QrApproveResult> approveSession({
    required String sid,
    required String otp,
    required String storeToken,
    required String username,
    required String password,
    String companyName = "",
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final sealed = sealPayload(
        {
          "storeToken": storeToken.trim().toUpperCase(),
          "username": username.trim().toLowerCase(),
          "password": password.trim(),
          "companyName": companyName.trim(),
          "ts": DateTime.now().millisecondsSinceEpoch,
        },
        otp,
      );
      final res = await httpClient
          .post(
            Uri.parse(endpoint),
            headers: const {"Content-Type": "application/json"},
            body: jsonEncode({
              "action": "APPROVE",
              "sid": sid,
              "sealedPayload": sealed,
            }),
          )
          .timeout(const Duration(seconds: 12));

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      if (res.statusCode == 200 && data["status"] == "SUCCESS") {
        return QrApproveResult(
          success: true,
          message: (data["message"] ?? "Web Workstation login approved!").toString(),
        );
      }
      final st = (data["status"] ?? "").toString().toUpperCase();
      final isExp = res.statusCode == 410 || st == "EXPIRED";
      return QrApproveResult(
        success: false,
        expired: isExp,
        message: (data["message"] ?? "Approval failed (HTTP ${res.statusCode})").toString(),
      );
    } catch (e) {
      return QrApproveResult(
        success: false,
        message: "Network error while approving QR login: $e",
      );
    } finally {
      if (shouldClose) httpClient.close();
    }
  }

  static Future<QrPollResult> pollSession({
    required String sid,
    required String otp,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.parse("$endpoint?sid=${Uri.encodeComponent(sid)}");
      final res = await httpClient.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        return QrPollResult(
          status: QrPollStatus.error,
          errorMessage: "Server responded with HTTP ${res.statusCode}",
        );
      }
      final data = jsonDecode(res.body);
      if (data is! Map) {
        return const QrPollResult(
          status: QrPollStatus.error,
          errorMessage: "Malformed QR status response",
        );
      }
      final st = (data["status"] ?? "").toString().toUpperCase();
      if (st == "EXPIRED") {
        return const QrPollResult(status: QrPollStatus.expired);
      }
      if (st == "PENDING") {
        return const QrPollResult(status: QrPollStatus.pending);
      }
      if (st == "APPROVED") {
        final sealed = (data["sealedPayload"] ?? "").toString();
        final plain = unsealPayload(sealed, otp);
        if (plain == null) {
          return const QrPollResult(
            status: QrPollStatus.error,
            errorMessage: "Encrypted QR payload verification failed.",
          );
        }
        final token = (plain["storeToken"] ?? "").toString().trim().toUpperCase();
        final user = (plain["username"] ?? "").toString().trim().toLowerCase();
        final pass = (plain["password"] ?? "").toString().trim();
        final comp = (plain["companyName"] ?? "").toString().trim();
        if (token.isEmpty || user.isEmpty || pass.isEmpty) {
          return const QrPollResult(
            status: QrPollStatus.error,
            errorMessage: "Incomplete store credentials in QR payload.",
          );
        }
        return QrPollResult(
          status: QrPollStatus.approved,
          credentials: QrLoginCredentials(
            storeToken: token,
            username: user,
            password: pass,
            companyName: comp,
          ),
        );
      }
      return QrPollResult(
        status: QrPollStatus.error,
        errorMessage: (data["message"] ?? "Unexpected status: $st").toString(),
      );
    } catch (_) {
      return const QrPollResult(
        status: QrPollStatus.error,
        errorMessage: "Connection interrupted while waiting for QR scan.",
      );
    } finally {
      if (shouldClose) httpClient.close();
    }
  }
}
