import 'package:flutter/material.dart';
import 'ai_setup_view.dart';
import 'vision_input_hub.dart';

class PharoahAiVision extends StatefulWidget {
  const PharoahAiVision({super.key});

  @override
  State<PharoahAiVision> createState() => _PharoahAiVisionState();
}

class _PharoahAiVisionState extends State<PharoahAiVision> {
  // Filhal manually set hai, baad me Gemini Key check karke update hoga
  bool isOnlineActive = true; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Pharoah AI Vision", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_suggest_rounded),
            tooltip: "AI Configuration",
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (c) => const AiSetupView()));
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 1. AI STATUS INDICATOR ---
            _buildStatusCard(),

            const SizedBox(height: 30),
            const Text(
              "SELECT SCANNING MODE",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5),
            ),
            const SizedBox(height: 15),

            // --- 2. PURCHASE AI BUTTON ---
            _buildActionCard(
              title: "PURCHASE AI",
              subtitle: "Scan Vendor bills to auto-fill Stock Inward.",
              icon: Icons.document_scanner_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9800), Color(0xFFF44336)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (c) => const VisionInputHub(mode: "PURCHASE")));
              },
            ),

            const SizedBox(height: 20),

            // --- 3. SALE AI BUTTON ---
            _buildActionCard(
              title: "SALE AI",
              subtitle: "Quick scan customer orders or invoices.",
              icon: Icons.bolt_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF0D47A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (c) => const VisionInputHub(mode: "SALE")));
              },
            ),

            const SizedBox(height: 40),
            
            // --- QUICK TIP CARD ---
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.indigo.withOpacity(0.08)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]
              ),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.orange, size: 28),
                  SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Pro Tip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          "Keep the bill flat and ensure good lighting for 99% accuracy.",
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // UI Helper: Status Indicator Card
  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isOnlineActive ? Colors.green.shade50 : Colors.grey.shade100,
              shape: BoxShape.circle
            ),
            child: Icon(
              isOnlineActive ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: isOnlineActive ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOnlineActive ? "PHAROAH AI - ONLINE" : "PHAROAH AI - OFFLINE",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
              Text(
                isOnlineActive ? "Advanced Hybrid Logic Active" : "Basic OCR Mode Active",
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // UI Helper: Main Action Buttons
  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(25),
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: (gradient as LinearGradient).colors.last.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8)
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            )
          ],
        ),
      ),
    );
  }
}
