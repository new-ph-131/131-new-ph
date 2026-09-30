import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pharoah_manager.dart';
import 'audit_logs_view.dart';

class FileManagementView extends StatefulWidget {
  const FileManagementView({super.key});
  @override State<FileManagementView> createState() => _FileManagementViewState();
}

class _FileManagementViewState extends State<FileManagementView> {
  String currentFy = "";

  @override
  void initState() {
    super.initState();
    _loadCurrentFY();
  }

  _loadCurrentFY() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { currentFy = prefs.getString('fy') ?? "2025-26"; });
  }

  void _showFYDialog() {
    final ph = Provider.of<PharoahManager>(context, listen: false);
    showDialog(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text("Select Working Financial Year"),
        children: ["2024-25", "2025-26", "2026-27", "2027-28"].map((year) {
          return SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: year == currentFy ? Colors.blue : Colors.grey),
                const SizedBox(width: 15),
                Text(year, style: TextStyle(fontWeight: year == currentFy ? FontWeight.bold : FontWeight.normal, color: year == currentFy ? Colors.blue : Colors.black)),
              ],
            ),
            onPressed: () async {
              if (year == currentFy) { Navigator.pop(c); return; }
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('fy', year);
              await ph.switchYear(year);
              if (mounted) {
                Navigator.pop(c);
                _showRestartAlert(year);
              }
            },
          );
        }).toList(),
      ),
    );
  }

  void _showRestartAlert(String newYear) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("FY Switch Complete"),
        content: Text("Ab aap $newYear ke data folder mein hain. Sahi data dikhane ke liye login dobara karein."),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text("GO TO LOGIN SCREEN"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(title: const Text("Data & FY Management"), backgroundColor: Colors.blueGrey.shade800, foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildActionCard(
            title: "Switch Financial Year",
            subtitle: "Current working year: $currentFy",
            icon: Icons.calendar_month_rounded,
            color: Colors.blue,
            onTap: _showFYDialog,
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
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
            child: const Text(
              "Dhyan Dein: Har saal ka data alag folder mein save hota hai. Ek saal ka bill dusre saal mein nahi dikhega.",
              // FIXED COLOR NAME HERE
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: ListTile(contentPadding: const EdgeInsets.all(15), leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)), trailing: const Icon(Icons.arrow_forward_ios, size: 14), onTap: onTap));
  }
}
