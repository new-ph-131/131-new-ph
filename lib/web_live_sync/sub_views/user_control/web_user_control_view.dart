// FILE: lib/web_live_sync/sub_views/user_control/web_user_control_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pharoah_erp/web_live_sync/pharoah_web_manager.dart';
import 'package:pharoah_erp/web_live_sync/web_models.dart';

class WebUserControlView extends StatefulWidget {
  final VoidCallback onBack;
  const WebUserControlView({super.key, required this.onBack});

  @override
  State<WebUserControlView> createState() => _WebUserControlViewState();
}

class _WebUserControlViewState extends State<WebUserControlView> {
  final TextEditingController authPassController = TextEditingController();
  final TextEditingController currentDevPassController = TextEditingController();
  final TextEditingController newDevPassController = TextEditingController();
  final TextEditingController confirmDevPassController = TextEditingController();
  final TextEditingController userPinController = TextEditingController();

  bool isObscuredAuth = true;
  bool isObscuredDev = true;

  String? authenticatedRole; // null, "DEV", or "USER"
  String? authErrorMessage;

  bool allowBatchHistoryToUser = false;
  bool userEnableBatchHistory = true;

  @override
  void initState() {
    super.initState();
    final webPh = Provider.of<PharoahWebManager>(context, listen: false);
    allowBatchHistoryToUser = webPh.appConfig.developerAllowBatchHistoryToUser;
    userEnableBatchHistory = webPh.appConfig.userEnableBatchHistory;
    userPinController.text = webPh.appConfig.userMasterPin;
  }

  @override
  void dispose() {
    authPassController.dispose();
    currentDevPassController.dispose();
    newDevPassController.dispose();
    confirmDevPassController.dispose();
    userPinController.dispose();
    super.dispose();
  }

  void _authenticate(PharoahWebManager webPh) {
    final input = authPassController.text.trim();
    if (input.isEmpty) {
      setState(() => authErrorMessage = "Please enter password or PIN.");
      return;
    }

    final devPass = webPh.appConfig.developerPassword.isNotEmpty ? webPh.appConfig.developerPassword : "Rawat@1122";
    final userPin = webPh.appConfig.userMasterPin.isNotEmpty ? webPh.appConfig.userMasterPin : "1234";

    if (input == devPass) {
      setState(() {
        authenticatedRole = "DEV";
        authErrorMessage = null;
        allowBatchHistoryToUser = webPh.appConfig.developerAllowBatchHistoryToUser;
        userEnableBatchHistory = webPh.appConfig.userEnableBatchHistory;
        userPinController.text = webPh.appConfig.userMasterPin;
      });
    } else if (input == userPin) {
      setState(() {
        authenticatedRole = "USER";
        authErrorMessage = null;
        allowBatchHistoryToUser = webPh.appConfig.developerAllowBatchHistoryToUser;
        userEnableBatchHistory = webPh.appConfig.userEnableBatchHistory;
        userPinController.text = webPh.appConfig.userMasterPin;
      });
    } else {
      setState(() {
        authErrorMessage = "Invalid password or PIN. Access denied.";
      });
    }
  }

  void _saveDeveloperSettings(PharoahWebManager webPh) {
    webPh.appConfig.developerAllowBatchHistoryToUser = allowBatchHistoryToUser;
    webPh.appConfig.userEnableBatchHistory = userEnableBatchHistory;
    if (userPinController.text.trim().isNotEmpty) {
      webPh.appConfig.userMasterPin = userPinController.text.trim();
    }
    webPh.pushUpdatedDataToCloud();
    webPh.notifyListeners();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✓ Developer permissions and user controls updated! Synced to cloud."),
        backgroundColor: Color(0xFF059669),
      ),
    );
  }

  void _changeDeveloperPassword(PharoahWebManager webPh) {
    final cur = currentDevPassController.text.trim();
    final n = newDevPassController.text.trim();
    final c = confirmDevPassController.text.trim();

    final activeDevPass = webPh.appConfig.developerPassword.isNotEmpty ? webPh.appConfig.developerPassword : "Rawat@1122";

    if (cur != activeDevPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Current Developer Password does not match!"), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (n.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("New Developer Password must be at least 6 characters."), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (n != c) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("New passwords do not match!"), backgroundColor: Colors.redAccent),
      );
      return;
    }

    webPh.appConfig.developerPassword = n;
    webPh.pushUpdatedDataToCloud();
    webPh.notifyListeners();

    currentDevPassController.clear();
    newDevPassController.clear();
    confirmDevPassController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✓ Developer Password successfully changed! Synced to cloud."),
        backgroundColor: Color(0xFF059669),
      ),
    );
    setState(() {});
  }

  void _saveUserSettings(PharoahWebManager webPh) {
    webPh.appConfig.userEnableBatchHistory = userEnableBatchHistory;
    if (userPinController.text.trim().isNotEmpty) {
      webPh.appConfig.userMasterPin = userPinController.text.trim();
    }
    webPh.pushUpdatedDataToCloud();
    webPh.notifyListeners();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✓ User preferences saved successfully!"),
        backgroundColor: Color(0xFF059669),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPh = Provider.of<PharoahWebManager>(context);

    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // 🏆 TOP HEADER BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  tooltip: "Back to Business Masters",
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFF87171), size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "User Control & Developer Security",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Configure Role Permissions, Master Password & Batch History Delegation",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (authenticatedRole != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => setState(() {
                      authenticatedRole = null;
                      authPassController.clear();
                    }),
                    icon: const Icon(Icons.lock_rounded, size: 16),
                    label: const Text("LOCK SESSION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
              ],
            ),
          ),

          // BODY
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: authenticatedRole == null
                  ? _buildWebAuthCard(webPh)
                  : authenticatedRole == "DEV"
                      ? _buildWebDeveloperPanel(webPh)
                      : _buildWebUserPanel(webPh),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebAuthCard(PharoahWebManager webPh) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.security_rounded, size: 52, color: Color(0xFFEF4444)),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Access Control Authentication",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Enter Developer Master Password or Staff User PIN to configure permissions.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 26),
              TextField(
                controller: authPassController,
                obscureText: isObscuredAuth,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: "Security Password / PIN",
                  labelStyle: const TextStyle(color: Colors.white60),
                  hintText: "Enter Developer Password or User PIN",
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  prefixIcon: const Icon(Icons.lock_rounded, color: Colors.white54),
                  suffixIcon: IconButton(
                    icon: Icon(isObscuredAuth ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                    onPressed: () => setState(() => isObscuredAuth = !isObscuredAuth),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                ),
                onSubmitted: (_) => _authenticate(webPh),
              ),
              if (authErrorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  authErrorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFF87171), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 22),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _authenticate(webPh),
                icon: const Icon(Icons.vpn_key_rounded, size: 18),
                label: const Text("UNLOCK ACCESS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.white54),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Entering the developer password grants full rights delegation. Entering user PIN accesses standard preferences.",
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebDeveloperPanel(PharoahWebManager webPh) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF991B1B), Color(0xFF7F1D1D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.military_tech_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "DEVELOPER MASTER CONTROL ACTIVE",
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                        SizedBox(height: 3),
                        Text(
                          "Master permission authority for Batch Traceability and staff access.",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text("DEVELOPER", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Card 1: Batch History Permission Delegation
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.table_chart_rounded, color: Color(0xFF2DD4BF), size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Batch Adjustment Audit History Permission",
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "Control whether regular users can see the Audit History button inside Batch Traceability.",
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 32),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "Show batches history in masters batches",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: const Text(
                      "When toggled ON, standard users will see the Audit History Ledger button inside Batch Traceability. Normal adjustments remain unrestricted.",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: allowBatchHistoryToUser,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => setState(() => allowBatchHistoryToUser = val),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _saveDeveloperSettings(webPh),
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text("APPLY & CLOUD SYNC", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Card 2: Developer Password Management
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.password_rounded, color: Color(0xFF60A5FA), size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Change Developer Master Password",
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "Default is 'Rawat@1122'. Update here and verify credentials.",
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 32),
                  TextField(
                    controller: currentDevPassController,
                    obscureText: isObscuredDev,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Current Developer Password",
                      labelStyle: const TextStyle(color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      prefixIcon: const Icon(Icons.lock_rounded, color: Colors.white54),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newDevPassController,
                          obscureText: isObscuredDev,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "New Developer Password",
                            labelStyle: const TextStyle(color: Colors.white60),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            prefixIcon: const Icon(Icons.key_rounded, color: Colors.white54),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          controller: confirmDevPassController,
                          obscureText: isObscuredDev,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "Confirm New Password",
                            labelStyle: const TextStyle(color: Colors.white60),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white54),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _changeDeveloperPassword(webPh),
                    icon: const Icon(Icons.lock_reset_rounded, size: 16),
                    label: const Text("UPDATE DEVELOPER PASSWORD", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Card 3: User PIN configuration
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.pin_rounded, color: Color(0xFFFBBF24), size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Staff User PIN Configuration",
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "PIN for standard staff members to access user preferences (Default: 1234)",
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 32),
                  TextField(
                    controller: userPinController,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: "Staff User PIN",
                      labelStyle: const TextStyle(color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      prefixIcon: const Icon(Icons.pin_rounded, color: Colors.white54),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _saveDeveloperSettings(webPh),
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text("SET USER PIN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebUserPanel(PharoahWebManager webPh) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "USER ACCESS CONTROL",
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 3),
                        Text(
                          "Staff Permissions & Local Preferences",
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                    ),
                    child: const Text("STAFF ACCESS", style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Card: Permission Status from Developer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: webPh.appConfig.developerAllowBatchHistoryToUser
                              ? const Color(0xFF10B981).withOpacity(0.2)
                              : const Color(0xFFF59E0B).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          webPh.appConfig.developerAllowBatchHistoryToUser
                              ? Icons.verified_user_rounded
                              : Icons.lock_rounded,
                          color: webPh.appConfig.developerAllowBatchHistoryToUser
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFBBF24),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              webPh.appConfig.developerAllowBatchHistoryToUser
                                  ? "Batch History in Masters: GRANTED BY DEVELOPER"
                                  : "Batch History in Masters: LOCKED BY DEVELOPER",
                              style: TextStyle(
                                color: webPh.appConfig.developerAllowBatchHistoryToUser
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFFFBBF24),
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              webPh.appConfig.developerAllowBatchHistoryToUser
                                  ? "You have permission to view the Batch Adjustment Audit Ledger in Batch Traceability."
                                  : "The developer has locked this feature. Please contact the administrator/developer with master credentials to grant access.",
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (webPh.appConfig.developerAllowBatchHistoryToUser) ...[
                    const Divider(color: Colors.white10, height: 32),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Display Batch History in Traceability",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: const Text(
                        "Keep this toggled ON to see the Audit History button inside Batch Traceability.",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      value: userEnableBatchHistory,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (val) => setState(() => userEnableBatchHistory = val),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _saveUserSettings(webPh),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text("SAVE PREFERENCES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
