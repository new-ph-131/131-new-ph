// FILE: lib/main.dart

import 'dart:ui'; // NAYA: Blur effect ke liye
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pharoah_manager.dart';
import 'login_view.dart';
import 'gateway/multi_setup_view.dart';
import 'gateway/company_list_screen.dart';
import 'gateway/company_control_panel.dart';
import 'main_control_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => PharoahManager(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

// WidgetsBindingObserver se hum phone ke minimize/maximize hone par nazar rakhenge
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Lifecycle monitor shuru
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Lifecycle monitor band
    super.dispose();
  }

  // --- APP BACKGROUND LOCK LOGIC ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    // Jaise hi app background mein jaye, ise lock kar do (Instant Lock)
    ph.handleAppLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PharoahManager>(
      builder: (context, ph, child) {
        return MaterialApp(
          key: ValueKey(ph.activeCompany?.id ?? "root"), 
          title: 'Pharoah ERP',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
            cardTheme: const CardThemeData(
              elevation: 3,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(15))),
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false, 
              elevation: 0,
              backgroundColor: Color(0xFF0D47A1),
              foregroundColor: Colors.white,
            ),
          ),
          // --- GLOBAL TOUCH LISTENER ---
          // Poori app ko Listener mein lapeta hai taaki har touch par timer reset ho
          home: Listener(
            onPointerDown: (_) => ph.resetInactivityTimer(),
            onPointerMove: (_) => ph.resetInactivityTimer(),
            child: Stack(
              children: [
                const AppGateway(), // Asli App niche chalegi
                
                // --- THE "CURTAIN" OVERLAY (PARDA) ---
                if (ph.isAppLocked && ph.isAdminAuthenticated)
                  const LockOverlayParda(),
              ],
            ),
          ),
        );
      }
    );
  }
}

// ===========================================================================
// 🛡️ APP GATEWAY: SMART FLOW (Selection -> Login -> Panel)
// ===========================================================================
class AppGateway extends StatelessWidget {
  const AppGateway({super.key});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);

    // 1. Initial Run: Setup Screen
    if (ph.companiesRegistry.isEmpty) {
      return const MultiSetupView(isFirstRun: true);
    }
    
    // 2. Company not selected: List Screen
    if (ph.activeCompany == null) {
      return const CompanyListScreen();
    }

    // 3. SECURE GATE: Login pehle (Dashboard/Control Panel se pehle)
    if (!ph.isAdminAuthenticated) {
      return const LoginView();
    }

    // 4. Authenticated: Control Panel (Where FY Selection happens)
    if (ph.currentFY.isEmpty) {
      return const CompanyControlPanelView();
    }

    // 5. Final: All Good -> Main ERP Shell
    return const MainControlShell();
  }
}

// ===========================================================================
// 🌫️ LOCK OVERLAY PARDA: GLASSMORPHISM EFFECT
// ===========================================================================
class LockOverlayParda extends StatelessWidget {
  const LockOverlayParda({super.key});

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context, listen: false);

    return Scaffold(
      backgroundColor: Colors.transparent, // Niche ka data dikhne ke liye
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // Blur effect
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black.withOpacity(0.6), // Halka kala rang
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_person_rounded, size: 80, color: Colors.white),
                const SizedBox(height: 20),
                const Text("SESSION LOCKED", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                Text("Inactivity for ${ph.activeCompany?.autoLockMinutes} minutes", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 40),
                
                // UNLOCK BUTTON
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700, 
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
                  ),
                  onPressed: () => ph.authenticateBiometric(), // Fingerprint scan trigger
                  icon: const Icon(Icons.fingerprint),
                  label: const Text("TAP TO UNLOCK", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                
                TextButton(
                  onPressed: () {
                    // Password fallback ke liye hum login status false karke 
                    // user ko wapas login screen par phek sakte hain
                    ph.authenticateAdmin(false);
                  }, 
                  child: const Text("Use Password Instead", style: TextStyle(color: Colors.white54))
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
