import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pharoah_manager.dart';
import 'audit_logs_view.dart';
import 'app_date_logic.dart';

class FileManagementView extends StatefulWidget {
  const FileManagementView({super.key});

  @override
  State<FileManagementView> createState() => _FileManagementViewState();
}

class _FileManagementViewState extends State<FileManagementView> {
  void _showFYDialog(PharoahManager ph) {
    final List<String> availableYears = ph.activeCompany != null && ph.activeCompany!.fYears.isNotEmpty
        ? AppDateLogic.sortFYList(ph.activeCompany!.fYears)
        : (ph.currentFY.isNotEmpty ? [ph.currentFY] : ["2025-26", "2026-27"]);
    final String currentFy = ph.currentFY;

    showDialog(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text("Select Working Financial Year", style: TextStyle(fontWeight: FontWeight.bold)),
        children: availableYears.map((year) {
          final bool isCurrent = year == currentFy;
          return SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: isCurrent ? Colors.blue : Colors.grey),
                const SizedBox(width: 15),
                Text(
                  year,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? Colors.blue : Colors.black87,
                  ),
                ),
                if (isCurrent) ...[
                  const Spacer(),
                  const Text("ACTIVE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ],
            ),
            onPressed: () async {
              if (year == currentFy) {
                Navigator.pop(c);
                return;
              }
              Navigator.pop(c);
              final prefs = await SharedPreferences.getInstance();
              if (ph.activeCompany != null) {
                await prefs.setString('active_fy_${ph.activeCompany!.id}', year);
              }
              await ph.switchYear(year);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Switched to $year workspace successfully!"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ph = Provider.of<PharoahManager>(context);
    final String currentFy = ph.currentFY.isNotEmpty ? ph.currentFY : "Not Selected";

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Data & FY Management"),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildActionCard(
            title: "Switch Financial Year",
            subtitle: "Current working year: $currentFy",
            icon: Icons.calendar_month_rounded,
            color: Colors.blue,
            onTap: () => _showFYDialog(ph),
          ),
          const SizedBox(height: 15),
          _buildActionCard(
            title: "Audit History",
            subtitle: "View logs for this financial year",
            icon: Icons.history_rounded,
            color: Colors.brown,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AuditLogsView())),
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Text(
              "Dhyan Dein: Har saal ka data alag folder mein save hota hai. Ek saal ka bill dusre saal mein nahi dikhega.",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}
