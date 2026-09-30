// FILE: lib/web_live_sync/components/web_login_card.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebLoginCard extends StatefulWidget {
  final String errorMessage;
  final bool isLoading;
  final Function(String storeToken, String username, String password) onLogin;

  const WebLoginCard({
    super.key,
    this.errorMessage = "",
    this.isLoading = false,
    required this.onLogin,
  });

  @override
  State<WebLoginCard> createState() => _WebLoginCardState();
}

class _WebLoginCardState extends State<WebLoginCard> {
  final storeKeyC = TextEditingController();
  final usernameC = TextEditingController();
  final passwordC = TextEditingController();
  bool isObscured = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('web_auth_store_token');
    final savedUser = prefs.getString('web_auth_username');
    if (savedToken != null && savedToken.isNotEmpty) {
      setState(() {
        storeKeyC.text = savedToken;
        if (savedUser != null && savedUser.isNotEmpty) {
          usernameC.text = savedUser;
        }
      });
    }
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(35),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0x4D22D3EE), width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 25, offset: Offset(0, 10))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: Color(0x1F22D3EE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront_rounded, size: 50, color: Colors.cyanAccent),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 25),

              if (widget.errorMessage.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
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

              _buildInput(storeKeyC, "STORE ACCESS KEY", Icons.vpn_key_rounded,
                  hint: "e.g. PH-LIVE-XXXX-XXXX", isCaps: true),
              const SizedBox(height: 15),
              _buildInput(usernameC, "USERNAME", Icons.person_rounded, hint: "e.g. admin"),
              const SizedBox(height: 15),
              _buildInput(
                passwordC,
                "PASSWORD",
                Icons.lock_rounded,
                isPass: true,
                isObscured: isObscured,
                onToggleObscure: () => setState(() => isObscured = !isObscured),
              ),
              const SizedBox(height: 30),

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
              const SizedBox(height: 20),
              const Text(
                "Powered by Pharoah ERP • Persistent Session Engine",
                style: TextStyle(color: Colors.white24, fontSize: 9),
              ),
            ],
          ),
        ),
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
