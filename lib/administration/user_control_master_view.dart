// FILE: lib/administration/user_control_master_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pharoah_manager.dart';
import '../logic/app_settings_model.dart';

class UserControlMasterView extends StatefulWidget {
  const UserControlMasterView({super.key});

  @override
  State<UserControlMasterView> createState() => _UserControlMasterViewState();
}

class _UserControlMasterViewState extends State<UserControlMasterView> {
  final TextEditingController authPassController = TextEditingController();
  final TextEditingController currentDevPassController = TextEditingController();
  final TextEditingController newDevPassController = TextEditingController();
  final TextEditingController confirmDevPassController = TextEditingController();
  final TextEditingController userPinController = TextEditingController();

  bool isObscuredAuth = true;
  bool isObscuredDev = true;
  bool isAuthenticating = false;

  // Session state: null = not authenticated, "DEV" = developer, "USER" = standard user
  String? authenticatedRole;
  String? authErrorMessage;

  // Working local state
  bool allowBatchHistoryToUser = false;
  bool userEnableBatchHistory = true;
  bool allowGstDiaryToUser = false;
  bool userEnableGstDiary = true;
  int _lastSyncedVersion = -1;
  int _lastSyncedUpdatedAt = -1;

  @override
  void initState() {
    super.initState();
    final ph = Provider.of<PharoahManager>(context, listen: false);
    allowBatchHistoryToUser = ph.config.developerAllowBatchHistoryToUser;
    userEnableBatchHistory = ph.config.userEnableBatchHistory;
    allowGstDiaryToUser = ph.config.developerAllowGstDiaryToUser;
    userEnableGstDiary = ph.config.userEnableGstDiary;
    userPinController.text = ph.config.userMasterPin;
    _lastSyncedVersion = ph.config.version;
    _lastSyncedUpdatedAt = ph.config.updatedAt;
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

  void _authenticate(PharoahManager ph) {
    final input = authPassController.text.trim();
    if (input.isEmpty) {
      setState(() => authErrorMessage = "Please enter password or PIN.");
      return;
    }

    final devPass = ph.config.developerPassword.isNotEmpty ? ph.config.developerPassword : "Rawat@1122";
    final userPin = ph.config.userMasterPin.isNotEmpty ? ph.config.userMasterPin : "1234";

    if (input == devPass) {
      setState(() {
        authenticatedRole = "DEV";
        authErrorMessage = null;
        allowBatchHistoryToUser = ph.config.developerAllowBatchHistoryToUser;
        userEnableBatchHistory = ph.config.userEnableBatchHistory;
        allowGstDiaryToUser = ph.config.developerAllowGstDiaryToUser;
        userEnableGstDiary = ph.config.userEnableGstDiary;
        userPinController.text = ph.config.userMasterPin;
      });
    } else if (input == userPin) {
      setState(() {
        authenticatedRole = "USER";
        authErrorMessage = null;
        allowBatchHistoryToUser = ph.config.developerAllowBatchHistoryToUser;
        userEnableBatchHistory = ph.config.userEnableBatchHistory;
        allowGstDiaryToUser = ph.config.developerAllowGstDiaryToUser;
        userEnableGstDiary = ph.config.userEnableGstDiary;
        userPinController.text = ph.config.userMasterPin;
      });
    } else {
      setState(() {
        authErrorMessage = "Invalid password or PIN. Access denied.";
      });
    }
  }

  void _saveDeveloperSettings(PharoahManager ph) {
    ph.config.developerAllowBatchHistoryToUser = allowBatchHistoryToUser;
    ph.config.userEnableBatchHistory = userEnableBatchHistory;
    ph.config.userEnableGstDiary = userEnableGstDiary;
    ph.config.developerAllowGstDiaryToUser = allowGstDiaryToUser;
    ph.config.userEnableGstDiary = userEnableGstDiary;
    if (userPinController.text.trim().isNotEmpty) {
      ph.config.userMasterPin = userPinController.text.trim();
    }
    ph.updateAppConfig(ph.config);
    _lastSyncedVersion = ph.config.version;
    _lastSyncedUpdatedAt = ph.config.updatedAt;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✓ Developer permissions and user controls updated! Synced across App and Web."),
        backgroundColor: Color(0xFF059669),
      ),
    );
  }

  void _changeDeveloperPassword(PharoahManager ph) {
    final cur = currentDevPassController.text.trim();
    final n = newDevPassController.text.trim();
    final c = confirmDevPassController.text.trim();

    final activeDevPass = ph.config.developerPassword.isNotEmpty ? ph.config.developerPassword : "Rawat@1122";

    if (cur != activeDevPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Current Developer Password does not match!"), backgroundColor: Colors.red),
      );
      return;
    }

    if (n.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("New Developer Password must be at least 6 characters."), backgroundColor: Colors.red),
      );
      return;
    }

    if (n != c) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("New passwords do not match!"), backgroundColor: Colors.red),
      );
      return;
    }

    ph.config.developerPassword = n;
    ph.updateAppConfig(ph.config);
    _lastSyncedVersion = ph.config.version;
    _lastSyncedUpdatedAt = ph.config.updatedAt;

    currentDevPassController.clear();
    newDevPassController.clear();
    confirmDevPassController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✓ Developer Password successfully changed! Synced to config."),
        backgroundColor: Color(0xFF059669),
      ),
    );
    setState(() {});
  }

  void _saveUserSettings(PharoahManager ph) {
    ph.config.userEnableBatchHistory = userEnableBatchHistory;
    ph.config.userEnableGstDiary = userEnableGstDiary;
    if (userPinController.text.trim().isNotEmpty) {
      ph.config.userMasterPin = userPinController.text.trim();
    }
    ph.updateAppConfig(ph.config);
    _lastSyncedVersion = ph.config.version;
    _lastSyncedUpdatedAt = ph.config.updatedAt;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✓ User preferences saved successfully!"),
        backgroundColor: Color(0xFF059669),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    if (ph.config.version != _lastSyncedVersion || ph.config.updatedAt != _lastSyncedUpdatedAt) {
      allowBatchHistoryToUser = ph.config.developerAllowBatchHistoryToUser;
      userEnableBatchHistory = ph.config.userEnableBatchHistory;
      allowGstDiaryToUser = ph.config.developerAllowGstDiaryToUser;
      userEnableGstDiary = ph.config.userEnableGstDiary;
      _lastSyncedVersion = ph.config.version;
      _lastSyncedUpdatedAt = ph.config.updatedAt;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("User Control & Security", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF991B1B),
        foregroundColor: Colors.white,
        actions: [
          if (authenticatedRole != null)
            TextButton.icon(
              onPressed: () => setState(() {
                authenticatedRole = null;
                authPassController.clear();
              }),
              icon: const Icon(Icons.lock_rounded, color: Colors.white70, size: 16),
              label: const Text("LOCK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: authenticatedRole == null
            ? _buildAuthScreen(ph)
            : authenticatedRole == "DEV"
                ? _buildDeveloperDashboard(ph)
                : _buildUserDashboard(ph),
      ),
    );
  }

  Widget _buildAuthScreen(PharoahManager ph) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF991B1B).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security_rounded, size: 48, color: Color(0xFF991B1B)),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  "User Control Center",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Enter Developer Master Password or User PIN to access your permission level.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: authPassController,
                  obscureText: isObscuredAuth,
                  decoration: InputDecoration(
                    labelText: "Security Password / PIN",
                    hintText: "Enter password or PIN",
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(isObscuredAuth ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => isObscuredAuth = !isObscuredAuth),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (_) => _authenticate(ph),
                ),
                if (authErrorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    authErrorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF991B1B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _authenticate(ph),
                  icon: const Icon(Icons.vpn_key_rounded, size: 18),
                  label: const Text("UNLOCK ACCESS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey.shade100),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Developer master recognition grants full permission configuration. User PIN provides staff access.",
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeveloperDashboard(PharoahManager ph) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF991B1B), Color(0xFFB91C1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.military_tech_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "DEVELOPER MASTER ACCESS",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Full Power & Permission Delegation Mode Active",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text("SUPERADMIN", style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Card 1: Master Batches Audit Permission Switch
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.table_chart_rounded, color: Color(0xFF0F766E), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Masters Batches Adjustment History Access",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                              ),
                              Text(
                                "Configure whether standard users can see audit history ledger in Batch Traceability",
                                style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Show batches history in masters batches",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: const Text(
                        "When enabled, standard users will see the Audit History button inside Batch Traceability.",
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      value: allowBatchHistoryToUser,
                      activeColor: const Color(0xFF059669),
                      onChanged: (val) {
                        setState(() => allowBatchHistoryToUser = val);
                        ph.config.developerAllowBatchHistoryToUser = val;
                        ph.updateAppConfig(ph.config);
                        _lastSyncedVersion = ph.config.version;
                        _lastSyncedUpdatedAt = ph.config.updatedAt;
                      },
                    ),
                    const Divider(height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Allow GST Diary to User",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: const Text(
                        "When enabled, users will see the GST Diary button in the GST Menu to compare Purchase vs Sale tax differences.",
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      value: allowGstDiaryToUser,
                      activeColor: const Color(0xFF059669),
                      onChanged: (val) {
                        setState(() => allowGstDiaryToUser = val);
                        ph.config.developerAllowGstDiaryToUser = val;
                        ph.updateAppConfig(ph.config);
                        _lastSyncedVersion = ph.config.version;
                        _lastSyncedUpdatedAt = ph.config.updatedAt;
                      },
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _saveDeveloperSettings(ph),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text("APPLY & SYNC PERMISSION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Card 2: Developer Password Management
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.password_rounded, color: Color(0xFF2563EB), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Developer Master Password",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                              ),
                              Text(
                                "Default is 'Rawat@1122'. You can change it securely here.",
                                style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    TextField(
                      controller: currentDevPassController,
                      obscureText: isObscuredDev,
                      decoration: InputDecoration(
                        labelText: "Current Developer Password",
                        prefixIcon: const Icon(Icons.lock_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newDevPassController,
                            obscureText: isObscuredDev,
                            decoration: InputDecoration(
                              labelText: "New Developer Password",
                              prefixIcon: const Icon(Icons.key_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: confirmDevPassController,
                            obscureText: isObscuredDev,
                            decoration: InputDecoration(
                              labelText: "Confirm New Password",
                              prefixIcon: const Icon(Icons.check_circle_outline_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _changeDeveloperPassword(ph),
                      icon: const Icon(Icons.lock_reset_rounded, size: 16),
                      label: const Text("UPDATE DEVELOPER PASSWORD", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Card 3: Standard User PIN
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.pin_rounded, color: Color(0xFFD97706), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "User PIN Configuration",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                              ),
                              Text(
                                "PIN used by normal staff to access User Control preferences",
                                style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    TextField(
                      controller: userPinController,
                      decoration: InputDecoration(
                        labelText: "Staff User PIN",
                        prefixIcon: const Icon(Icons.pin_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _saveDeveloperSettings(ph),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text("SET USER PIN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDashboard(PharoahManager ph) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
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
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "USER ACCESS CONTROL",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Staff Permissions & Local Preferences",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text("STAFF MODE", style: TextStyle(color: Color(0xFF34D399), fontSize: 10.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Card: Permission Status from Developer
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ph.config.developerAllowBatchHistoryToUser
                                ? const Color(0xFF10B981).withOpacity(0.12)
                                : const Color(0xFFF59E0B).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            ph.config.developerAllowBatchHistoryToUser
                                ? Icons.verified_user_rounded
                                : Icons.lock_rounded,
                            color: ph.config.developerAllowBatchHistoryToUser
                                ? const Color(0xFF059669)
                                : const Color(0xFFD97706),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ph.config.developerAllowBatchHistoryToUser
                                    ? "Batches Audit History: ALLOWED BY DEVELOPER"
                                    : "Batches Audit History: LOCKED BY DEVELOPER",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: ph.config.developerAllowBatchHistoryToUser
                                      ? const Color(0xFF059669)
                                      : const Color(0xFFD97706),
                                ),
                              ),
                              Text(
                                ph.config.developerAllowBatchHistoryToUser
                                    ? "Developer has granted access to view the Batch Adjustment Audit Ledger in Batch Traceability."
                                    : "This option requires Developer authorization. Ask your developer to allow it from Developer Master.",
                                style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (ph.config.developerAllowBatchHistoryToUser) ...[
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          "Display Batch History in Traceability",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: const Text(
                          "Turn on to view the Audit History button in your Batch Traceability screen.",
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                        value: userEnableBatchHistory,
                        activeColor: const Color(0xFF059669),
                        onChanged: (val) {
                          setState(() => userEnableBatchHistory = val);
                          ph.config.userEnableBatchHistory = val;
                          ph.updateAppConfig(ph.config);
                          _lastSyncedVersion = ph.config.version;
                          _lastSyncedUpdatedAt = ph.config.updatedAt;
                        },
                      ),
                    ],
                    if (ph.config.developerAllowGstDiaryToUser) ...[
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          "Display GST Diary in GST Menu",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: const Text(
                          "Turn on to view the GST Diary button in your GST Menu.",
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                        value: userEnableGstDiary,
                        activeColor: const Color(0xFF059669),
                        onChanged: (val) {
                          setState(() => userEnableGstDiary = val);
                          ph.config.userEnableGstDiary = val;
                          ph.updateAppConfig(ph.config);
                          _lastSyncedVersion = ph.config.version;
                          _lastSyncedUpdatedAt = ph.config.updatedAt;
                        },
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _saveUserSettings(ph),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text("SAVE PREFERENCES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
