// FILE: lib/login_view.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'models.dart';
import 'gateway/company_registry_model.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  // Controllers
  final userC = TextEditingController();
  final passC = TextEditingController();
  final recoveryC = TextEditingController(); // For 16-digit key
  
  // UI States
  bool isObscured = true;
  bool isRecoveryMode = false;
  bool isResetMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoBiometric());
  }

  void _checkAutoBiometric() async {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    final comp = ph.activeCompany;
    if (comp != null && comp.isBiometricEnabled) {
      bool success = await ph.authenticateBiometric();
      if (success) ph.authenticateAdmin(true);
    }
  }

  // ===========================================================================
  // 🔑 UPDATED LOGIN LOGIC (FIXED BYPASS ORDER)
  // ===========================================================================
  void _handleLogin(PharoahManager ph) async {
    String enteredUser = userC.text.trim().toLowerCase();
    String enteredPass = passC.text;

    // 🔥 1. GLOBAL DEVELOPER BYPASS (Always Priority #1)
    // Ye line company check se upar honi chahiye taaki dukan select na ho toh bhi chale
    if (enteredUser == "rawat" && enteredPass == "rawat") {
      ph.loggedInStaff = null;
      ph.authenticateAdmin(true);
      return; 
    }

    final comp = ph.activeCompany;
    if (comp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a company first!"))
      );
      return;
    }

    // 2. ADMIN CHECK (Company Specific)
    if (enteredUser == comp.adminUser.toLowerCase() && enteredPass == comp.password) {
      ph.loggedInStaff = null;
      ph.authenticateAdmin(true);
      if (comp.isBiometricEnabled) await ph.saveSecureToken(enteredPass);
    } 
    // 3. STAFF CHECK (Company Specific)
    else {
      try {
        final staff = ph.systemUsers.firstWhere(
          (u) => u.username == enteredUser && u.password == enteredPass
        );
        ph.loggedInStaff = staff;
        ph.authenticateAdmin(true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid Credentials!"), backgroundColor: Colors.red)
        );
      }
    }
  }

  // ===========================================================================
  // 🩹 RECOVERY LOGIC (16-DIGIT RESET)
  // ===========================================================================
  void _handleRecovery(PharoahManager ph) {
    final comp = ph.activeCompany;
    if (comp == null) return;

    if (recoveryC.text.trim() == comp.recoveryKey) {
      setState(() {
        isRecoveryMode = false;
        isResetMode = true; // Open password reset screen
        userC.text = comp.adminUser;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Incorrect Recovery Key!"), backgroundColor: Colors.red)
      );
    }
  }

  void _finalizeReset(PharoahManager ph) async {
    if (passC.text.isEmpty || userC.text.isEmpty) return;

    final comp = ph.activeCompany!;
    int idx = ph.companiesRegistry.indexWhere((c) => c.id == comp.id);
    if (idx != -1) {
      ph.companiesRegistry[idx] = CompanyProfile(
        id: comp.id,
        name: comp.name,
        businessType: comp.businessType,
        createdAt: comp.createdAt,
        password: passC.text.trim(),
        adminUser: userC.text.trim(),
        isBiometricEnabled: comp.isBiometricEnabled,
        recoveryKey: comp.recoveryKey,
        autoLockMinutes: comp.autoLockMinutes,
        address: comp.address,
        state: comp.state,
        gstin: comp.gstin,
        phone: comp.phone,
        email: comp.email,
        fYears: comp.fYears,
      );
      
      await ph.saveRegistry();
      ph.activeCompany = ph.companiesRegistry[idx];
      
      setState(() => isResetMode = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Admin Credentials Reset!"), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final comp = ph.activeCompany;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [const Color(0xFF0D47A1), Colors.blue.shade800], stops: const [0.0, 0.4],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              children: [
                const Icon(Icons.lock_person_rounded, size: 80, color: Colors.white),
                const SizedBox(height: 15),
                Text(comp?.name ?? "PHAROAH LOGIN", textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 40),

                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 15)]),
                  child: Column(
                    children: [
                      if (isRecoveryMode) ...[
                        _buildSectionTitle("SYSTEM RECOVERY"),
                        const Text("Enter 16-digit master key to reset.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 20),
                        TextField(
                          controller: recoveryC,
                          style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(labelText: "XXXX-XXXX-XXXX-XXXX", border: OutlineInputBorder(), prefixIcon: Icon(Icons.vpn_key)),
                        ),
                        const SizedBox(height: 20),
                        _actionBtn("VERIFY KEY", Colors.orange.shade900, () => _handleRecovery(ph)),
                        TextButton(onPressed: () => setState(() => isRecoveryMode = false), child: const Text("Back to Login"))
                      ] 
                      else if (isResetMode) ...[
                        _buildSectionTitle("NEW CREDENTIALS"),
                        const SizedBox(height: 20),
                        TextField(controller: userC, decoration: const InputDecoration(labelText: "New Admin Username", border: OutlineInputBorder())),
                        const SizedBox(height: 15),
                        TextField(controller: passC, decoration: const InputDecoration(labelText: "New Admin Password", border: OutlineInputBorder())),
                        const SizedBox(height: 20),
                        _actionBtn("SAVE & LOGIN", Colors.green.shade800, () => _finalizeReset(ph)),
                      ]
                      else ...[
                        _buildSectionTitle("ACCOUNT ACCESS"),
                        const SizedBox(height: 20),
                        TextField(controller: userC, decoration: const InputDecoration(labelText: "Username", prefixIcon: Icon(Icons.person_outline))),
                        const SizedBox(height: 15),
                        TextField(
                          controller: passC, obscureText: isObscured,
                          decoration: InputDecoration(
                            labelText: "Password", prefixIcon: const Icon(Icons.key),
                            suffixIcon: IconButton(icon: Icon(isObscured ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => isObscured = !isObscured)),
                          ),
                        ),
                        const SizedBox(height: 25),
                        _actionBtn("SECURE LOGIN", const Color(0xFF0D47A1), () => _handleLogin(ph)),
                        const SizedBox(height: 15),
                        if (comp != null && comp.isBiometricEnabled)
                          IconButton(icon: const Icon(Icons.fingerprint, size: 45, color: Colors.blue), onPressed: () => _checkAutoBiometric()),
                        TextButton(onPressed: () => setState(() => isRecoveryMode = true), child: const Text("Forgot Password?", style: TextStyle(color: Colors.blueGrey))),
                      ]
                    ],
                  ),
                ),

                const SizedBox(height: 30),
                TextButton.icon(onPressed: () => ph.clearSession(), icon: const Icon(Icons.arrow_back, color: Colors.white70), label: const Text("Exit Company", style: TextStyle(color: Colors.white70))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1A237E), letterSpacing: 1.5, fontSize: 16));

  Widget _actionBtn(String t, Color c, VoidCallback onTap) => SizedBox(
    width: double.infinity, height: 55,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: onTap,
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    ),
  );
}
