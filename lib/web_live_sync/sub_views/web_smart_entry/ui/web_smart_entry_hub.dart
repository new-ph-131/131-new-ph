import 'package:flutter/material.dart';
import 'medilente_entry_screen.dart';
import 'amazon_entry_screen.dart';

class WebSmartEntryHub extends StatefulWidget {
  final VoidCallback onBack;

  const WebSmartEntryHub({super.key, required this.onBack});

  @override
  State<WebSmartEntryHub> createState() => _WebSmartEntryHubState();
}

class _WebSmartEntryHubState extends State<WebSmartEntryHub> {
  String selectedSub = "HUB"; // HUB, MEDILENTE, AMAZON

  @override
  Widget build(BuildContext context) {
    if (selectedSub == "MEDILENTE") {
      return MedilenteEntryScreen(onBack: () => setState(() => selectedSub = "HUB"));
    }
    if (selectedSub == "AMAZON") {
      return AmazonEntryScreen(onBack: () => setState(() => selectedSub = "HUB"));
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text("BACK TO DASHBOARD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.auto_fix_high_rounded, color: Color(0xFF38BDF8), size: 24),
              const SizedBox(width: 10),
              const Text(
                "SMART ENTRY HUB",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Text(
            "SELECT IMPORT PLATFORM",
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth > 700 ? 2 : 1;

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                childAspectRatio: 1.5,
                children: [
                  _smartOptionCard(
                    title: "1. MEDILENTE",
                    subtitle: "Pharma distributor automatic purchase / order inward entry",
                    icon: Icons.medical_services_rounded,
                    color: const Color(0xFF10B981),
                    onTap: () => setState(() => selectedSub = "MEDILENTE"),
                  ),
                  _smartOptionCard(
                    title: "2. AMAZON",
                    subtitle: "E-Commerce merchant B2B / MTR sales report inward entry",
                    icon: Icons.shopping_bag_rounded,
                    color: const Color(0xFFF59E0B),
                    onTap: () => setState(() => selectedSub = "AMAZON"),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _smartOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF19243B), Color(0xFF0F172A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withAlpha(100), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withAlpha(90)),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}
