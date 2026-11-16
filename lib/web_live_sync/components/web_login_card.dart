// FILE: lib/web_live_sync/components/web_login_card.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../qr_login_service.dart';

class WebLoginCard extends StatefulWidget {
  final String errorMessage;
  final bool isLoading;
  final Function(String storeToken, String username, String password) onLogin;
  final http.Client? qrHttpClient;

  const WebLoginCard({
    super.key,
    this.errorMessage = "",
    this.isLoading = false,
    required this.onLogin,
    this.qrHttpClient,
  });

  @override
  State<WebLoginCard> createState() => _WebLoginCardState();
}

class _WebLoginCardState extends State<WebLoginCard> {
  final storeKeyC = TextEditingController();
  final usernameC = TextEditingController();
  final passwordC = TextEditingController();
  bool isObscured = true;

  // Secure QR Login Session state
  QrSessionChallenge? _challenge;
  bool _qrInitializing = true;
  bool _qrExpired = false;
  bool _qrApprovedConnecting = false;
  bool _isPollInFlight = false;
  String _qrStatusHint = "Waiting for scan from mobile app...";
  int _remainingSeconds = QrLoginService.sessionTtlSeconds;
  Timer? _countdownTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _startQrSession();
  }

  @override
  void didUpdateWidget(covariant WebLoginCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading && !widget.isLoading && _qrApprovedConnecting) {
      if (widget.errorMessage.isNotEmpty) {
        setState(() {
          _qrApprovedConnecting = false;
          _qrExpired = true;
          _qrStatusHint = "Login failed. Refresh QR to try again.";
        });
      }
    }
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('web_auth_store_token');
    final savedUser = prefs.getString('web_auth_username');
    if (savedToken != null && savedToken.isNotEmpty && mounted) {
      setState(() {
        storeKeyC.text = savedToken;
        if (savedUser != null && savedUser.isNotEmpty) {
          usernameC.text = savedUser;
        }
      });
    }
  }

  void _stopQrTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _startQrSession() async {
    _stopQrTimers();
    final nextChallenge = QrLoginService.createLocalChallenge();
    if (!mounted) return;
    setState(() {
      _challenge = nextChallenge;
      _qrInitializing = true;
      _qrExpired = false;
      _qrApprovedConnecting = false;
      _remainingSeconds = QrLoginService.sessionTtlSeconds;
      _qrStatusHint = "Generating secure session...";
    });

    final ok = await QrLoginService.initSession(
      nextChallenge.sid,
      client: widget.qrHttpClient,
    );
    if (!mounted || _challenge?.sid != nextChallenge.sid) return;

    if (!ok) {
      setState(() {
        _qrInitializing = false;
        _qrExpired = true;
        _qrStatusHint = "Could not reach QR pairing relay. Tap Refresh QR.";
      });
      return;
    }

    setState(() {
      _qrInitializing = false;
      _qrExpired = false;
      _qrStatusHint = "Scan from Mobile App to login";
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        _stopQrTimers();
        setState(() {
          _remainingSeconds = 0;
          _qrExpired = true;
          _qrStatusHint = "QR code expired. Tap Refresh QR.";
        });
      } else {
        setState(() => _remainingSeconds--);
      }
    });

    _pollTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      _pollCurrentSession();
    });
  }

  Future<void> _pollCurrentSession() async {
    final active = _challenge;
    if (!mounted ||
        active == null ||
        _qrExpired ||
        _qrApprovedConnecting ||
        _isPollInFlight ||
        widget.isLoading) {
      return;
    }
    _isPollInFlight = true;
    try {
      final res = await QrLoginService.pollSession(
        sid: active.sid,
        otp: active.otp,
        client: widget.qrHttpClient,
      );
      if (!mounted || _challenge?.sid != active.sid) return;

      if (res.status == QrPollStatus.expired) {
        _stopQrTimers();
        setState(() {
          _qrExpired = true;
          _qrStatusHint = "QR code expired. Tap Refresh QR.";
        });
      } else if (res.status == QrPollStatus.approved && res.credentials != null) {
        _stopQrTimers();
        final creds = res.credentials!;
        setState(() {
          _qrApprovedConnecting = true;
          _qrStatusHint = "Approved! Logging into workstation...";
          storeKeyC.text = creds.storeToken;
          usernameC.text = creds.username;
        });
        widget.onLogin(creds.storeToken, creds.username, creds.password);
      } else if (res.status == QrPollStatus.error && res.errorMessage.isNotEmpty) {
        setState(() {
          _qrStatusHint = res.errorMessage;
        });
      }
    } finally {
      _isPollInFlight = false;
    }
  }

  @override
  void dispose() {
    _stopQrTimers();
    storeKeyC.dispose();
    usernameC.dispose();
    passwordC.dispose();
    super.dispose();
  }

  void _submit() {
    final token = storeKeyC.text.trim().toUpperCase();
    final user = usernameC.text.trim().toLowerCase();
    final pass = passwordC.text.trim();
    if (token.isEmpty || user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Store Key, Username & Password are required!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    widget.onLogin(token, user, pass);
  }

  String _formatCountdown(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 780;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: isWide ? 860 : 460,
              padding: EdgeInsets.all(isWide ? 36 : 30),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: const Color(0x4D22D3EE), width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 25, offset: Offset(0, 10))
                ],
              ),
              child: isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 11, child: _buildManualColumn()),
                          _buildVerticalOrDivider(),
                          Expanded(flex: 9, child: _buildQrPanel()),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildManualColumn(),
                        _buildHorizontalOrDivider(),
                        _buildQrPanel(),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVerticalOrDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        children: [
          const Expanded(child: VerticalDivider(color: Colors.white12, thickness: 1)),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              "OR",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const Expanded(child: VerticalDivider(color: Colors.white12, thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildHorizontalOrDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Colors.white12, thickness: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              "OR SCAN QR CODE",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Colors.white12, thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildManualColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0x1F22D3EE),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.storefront_rounded, size: 46, color: Colors.cyanAccent),
        ),
        const SizedBox(height: 18),
        const Text(
          "PHAROAH WEB WORKSTATION",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "Enter Store Key & Credentials to login",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 24),
        if (widget.errorMessage.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: const Color(0x26EF4444),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x66EF4444)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.errorMessage,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        _buildInput(
          storeKeyC,
          "STORE ACCESS KEY",
          Icons.vpn_key_rounded,
          hint: "e.g. PH-LIVE-XXXX-XXXX",
          isCaps: true,
        ),
        const SizedBox(height: 14),
        _buildInput(usernameC, "USERNAME", Icons.person_rounded, hint: "e.g. admin"),
        const SizedBox(height: 14),
        _buildInput(
          passwordC,
          "PASSWORD",
          Icons.lock_rounded,
          isPass: true,
          isObscured: isObscured,
          onToggleObscure: () => setState(() => isObscured = !isObscured),
        ),
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: widget.isLoading ? null : _submit,
            icon: widget.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.login_rounded, size: 20),
            label: Text(
              widget.isLoading ? "CONNECTING..." : "LOGIN TO WORKSTATION",
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          "Powered by Pharoah ERP • Persistent Session Engine",
          style: TextStyle(color: Colors.white24, fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildQrPanel() {
    final activePayload = _challenge?.qrPayload ?? "";
    final bool showOverlay = _qrInitializing || _qrExpired || _qrApprovedConnecting;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.qr_code_scanner_rounded, color: Colors.cyanAccent, size: 20),
              SizedBox(width: 8),
              Text(
                "INSTANT QR LOGIN",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Scan with Pharoah Mobile App",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 18),
          Container(
            width: 210,
            height: 210,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 6)),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (activePayload.isNotEmpty)
                  Opacity(
                    opacity: showOverlay ? 0.16 : 1.0,
                    child: QrImageView(
                      key: ValueKey<String>(activePayload),
                      data: activePayload,
                      version: QrVersions.auto,
                      size: 186,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0F172A),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                if (_qrInitializing)
                  const CircularProgressIndicator(color: Color(0xFF0F172A), strokeWidth: 2.5)
                else if (_qrApprovedConnecting)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(color: Colors.teal, strokeWidth: 3),
                      SizedBox(height: 10),
                      Text(
                        "APPROVED!\nLOGGING IN...",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.teal,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  )
                else if (_qrExpired)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh_rounded, color: Color(0xFF0F172A), size: 34),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.cyanAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: widget.isLoading ? null : _startQrSession,
                        child: const Text(
                          "REFRESH QR",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _qrExpired ? const Color(0x26EF4444) : const Color(0x1F22D3EE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _qrExpired
                      ? "EXPIRED"
                      : (_qrApprovedConnecting
                          ? "AUTHORIZED"
                          : "Expires in ${_formatCountdown(_remainingSeconds)}"),
                  style: TextStyle(
                    color: _qrExpired ? Colors.redAccent : Colors.cyanAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: "Generate New QR",
                onPressed: (widget.isLoading || _qrApprovedConnecting) ? null : _startQrSession,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _qrStatusHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: const Text(
              "1. Open Pharoah App on phone\n2. Go to Settings → Live Web Access\n3. Tap 'Scan Web Login QR' & Approve",
              style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, IconData icon,
      {bool isPass = false,
      bool isCaps = false,
      String hint = "",
      bool isObscured = false,
      VoidCallback? onToggleObscure}) {
    return TextField(
      controller: ctrl,
      obscureText: isPass ? isObscured : false,
      textCapitalization: isCaps ? TextCapitalization.characters : TextCapitalization.none,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(isObscured ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white54, size: 18),
                onPressed: onToggleObscure,
              )
            : null,
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      ),
    );
  }
}
